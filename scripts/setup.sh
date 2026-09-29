#!/usr/bin/env bash
# Brings one stack up from scratch, records boot time, creates an API key and
# appends it to .env.bench.   scripts/setup.sh <ddcore|frappe>
set -euo pipefail
cd "$(dirname "$0")/.."
T=${1:?target: ddcore | frappe}
C="docker compose -f compose/docker-compose.$T.yml"
touch .env.bench

$C down -v --remove-orphans >/dev/null 2>&1 || true
$C build -q

if [ "$T" = ddcore ]; then PORT=8101; READY=/readyz; else PORT=8102; READY=/api/method/ping; fi

# Boot = first-time boot: database init + migrations/site creation + server ready.
start=$(date +%s)
$C up -d
until curl -fsS -o /dev/null "http://localhost:$PORT$READY" 2>/dev/null; do
  sleep 1
  if (( $(date +%s) - start > 600 )); then $C logs --tail 40; echo "[$T] not ready after 600s" >&2; exit 1; fi
done
first_boot=$(( $(date +%s) - start ))

# Warm boot: the app container alone, schema already in place.
start=$(python3 -c 'import time;print(time.time())')
$C restart app >/dev/null
until curl -fsS -o /dev/null "http://localhost:$PORT$READY" 2>/dev/null; do sleep 0.1; done
warm_boot=$(python3 -c "import time;print(round(time.time()-$start,2))")

if [ "$T" = ddcore ]; then
  token=$($C exec -T app ddcore apikey Admin --label bench | grep -Eo '[A-Za-z0-9_-]+:[A-Za-z0-9_-]+' | tail -1)
else
  out=$($C exec -T app bench --site localhost execute frappe.core.doctype.user.user.generate_keys --kwargs "{'user':'Administrator'}")
  secret=$(echo "$out" | python3 -c 'import sys,json,ast;s=sys.stdin.read();d=json.loads(s[s.index("{"):]) ;print(d["api_secret"])')
  key=$($C exec -T app bench --site localhost execute frappe.db.get_value --args "['User','Administrator','api_key']" | tr -d '"\r\n ')
  token="$key:$secret"
fi

var="TOKEN_$(echo "$T" | tr a-z A-Z)"
grep -v "^$var=" .env.bench > .env.bench.tmp || true
mv .env.bench.tmp .env.bench
echo "$var=$token" >> .env.bench
mkdir -p results/latest
echo "{\"target\":\"$T\",\"first_boot_s\":$first_boot,\"warm_boot_s\":$warm_boot}" > "results/latest/boot-$T.json"
echo "[$T] first boot ${first_boot}s, warm boot ${warm_boot}s, token in .env.bench"
