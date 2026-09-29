#!/usr/bin/env bash
# Phase 1: simple metrics with oha + docker stats.   scripts/phase1.sh <ddcore|frappe> [out-dir]
# Expects the stack up (scripts/setup.sh) and seeded (npm run seed -- <target>).
set -euo pipefail
cd "$(dirname "$0")/.."
T=${1:?target: ddcore | frappe}
OUT=${2:-results/latest}
mkdir -p "$OUT/$T"
set -a; . ./.env.bench; set +a
TOKEN_VAR="TOKEN_$(echo "$T" | tr a-z A-Z)"; TOKEN=${!TOKEN_VAR}
PROJECT="bench-$T"
DUR=${DUR:-30s}
N=${N:-1000}

# ---- resources: image size and idle memory of the whole stack ----
docker image inspect "ddcore-bench/$T:$( [ "$T" = ddcore ] && echo "${DDCORE_VERSION:-0.21.10}" || echo latest)" \
  -f '{{.Size}}' > "$OUT/$T/image_bytes"
echo "[$T] idle 60s before sampling memory…"; sleep "${IDLE_WAIT:-60}"
docker stats --no-stream --format '{{.Name}},{{.MemUsage}},{{.CPUPerc}}' \
  $(docker ps -q --filter "label=com.docker.compose.project=$PROJECT") > "$OUT/$T/idle_stats.csv"

# ---- endpoints: the URLs come from the adapter so both targets hit the same thing ----
node --input-type=module -e "
import { target } from './k6/lib/adapter.js';
const t = target('$T', { token: process.env.$TOKEN_VAR });
const get = async (r) => (await fetch(r.url, { headers: t.headers })).json();
const orders = (await get(t.list('Bench Order', { fields: ['id', 'customer'], orderBy: 'order_date desc', limit: 1 }))).data;
const o = orders[0];
const insert = t.insert('Bench Order', { customer: o.customer, order_date: '2025-06-01',
  items: [1,2,3,4,5].map((i) => ({ item: 'SKU-' + i, qty: i, rate: 10.5 })) });
const eps = {
  ping: t.ping(),
  get_order: t.get('Bench Order', t.idOf(o)),
  list_orders: t.list('Bench Order', { fields: ['id', 'customer', 'status', 'total', 'order_date'],
    filters: { status: 'Paid' }, orderBy: 'order_date desc', limit: 20 }),
  summary: t.summary(o.customer),
  insert_order: insert,
};
for (const [k, r] of Object.entries(eps)) console.log([k, r.method, r.url, r.body ?? ''].join('\t'));
" > "$OUT/$T/endpoints.tsv"

run() { # name method url body conc mode(n|z) value
  local name=$1 m=$2 url=$3 body=$4 c=$5 mode=$6 v=$7
  local args=(--no-tui --output-format json -m "$m" -c "$c" -H "Authorization: token $TOKEN" -H "Accept: application/json")
  [ -n "$body" ] && args+=(-H "Content-Type: application/json" -d "$body")
  [ "$mode" = n ] && args+=(-n "$v") || args+=(-z "$v" -w)
  oha "${args[@]}" "$url" > "$OUT/$T/$name.c$c.json"
  python3 - "$OUT/$T/$name.c$c.json" "$T" "$name" "$c" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); s = d["summary"]; p = d["latencyPercentiles"]
ms = lambda v: f"{v * 1000:.1f}ms" if v is not None else "n/a"
errs = d.get("errorDistribution") or {}
print(f"[{sys.argv[2]}] {sys.argv[3]} c={sys.argv[4]}  rps={s['requestsPerSec']:.0f}  p50={ms(p['p50'])}  "
      f"p95={ms(p['p95'])}  ok={(s['successRate'] or 0) * 100:.1f}%" + (f"  errors={errs}" if errs else ""))
PY
}

# warm-up, discarded
while IFS=$'\t' read -r name m url body; do
  oha --no-tui --output-format quiet -m "$m" -c 4 -z 10s -H "Authorization: token $TOKEN" \
    ${body:+-H "Content-Type: application/json" -d "$body"} "$url" >/dev/null
done < <(grep -v insert_order "$OUT/$T/endpoints.tsv")

# latency (c=1, N requests) then throughput (c=10 and c=50 for DUR); inserts last
for phase in reads insert; do
  while IFS=$'\t' read -r name m url body; do
    if [ "$phase" = reads ] && [ "$name" = insert_order ]; then continue; fi
    if [ "$phase" = insert ] && [ "$name" != insert_order ]; then continue; fi
    run "$name" "$m" "$url" "$body" 1 n "$N"
    for c in 10 50; do
      # sample stack CPU/memory during the run
      (docker stats --format '{{.Name}},{{.MemUsage}},{{.CPUPerc}}' \
        $(docker ps -q --filter "label=com.docker.compose.project=$PROJECT") > "$OUT/$T/$name.c$c.stats.csv") &
      sp=$!
      run "$name" "$m" "$url" "$body" "$c" z "$DUR"
      kill $sp 2>/dev/null || true
    done
  done < "$OUT/$T/endpoints.tsv"
done
echo "[$T] results in $OUT/$T"
