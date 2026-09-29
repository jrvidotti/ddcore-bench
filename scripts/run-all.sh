#!/usr/bin/env bash
# Every test, end to end, with the data already seeded on both targets.
#   scripts/run-all.sh [out-dir]      (make all)
# A failing run (k6 thresholds, errors) is recorded and the sequence goes on.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-results/full-$(date +%Y%m%d-%H%M)}
mkdir -p "$OUT/k6"
export OUTDIR="$OUT/k6"
log() { echo "=== $(date +%H:%M:%S) $*"; }

up() { # target [cpus]: that target's stack only, app recreated with the given CPU limit
  local t=$1 cpus=${2:-2} other
  other=$([ "$t" = ddcore ] && echo frappe || echo ddcore)
  docker compose -f "compose/docker-compose.$other.yml" stop >/dev/null 2>&1 || true
  docker compose -f "compose/docker-compose.$t.yml" start >/dev/null 2>&1
  APP_CPUS=$cpus GUNICORN_WORKERS=$((2 * ${cpus%.*} + 1)) \
    docker compose -f "compose/docker-compose.$t.yml" up -d --no-deps app >/dev/null 2>&1
  scripts/wait-ready.sh "$t"
}

k6run() { # name target script args…
  local name=$1 t=$2; shift 2
  log "k6 $name on $t"
  NAME=$name scripts/k6.sh "$t" "$@" 2>&1 | grep -vE "^\s*(running|default|mix|op) +\[" || true
}

log "phase 1"
scripts/run-phase1.sh "$OUT/phase1"

for t in ddcore frappe; do
  up "$t" 2
  k6run smoke "$t" k6/scenarios/mix.js
  k6run ramp "$t" k6/scenarios/mix.js -e PROFILE=ramp
  k6run rate100 "$t" k6/scenarios/mix.js -e PROFILE=rate -e RATE=100 -e DURATION=2m
  for op in ping get list summary; do
    k6run "crud-$op" "$t" k6/scenarios/crud.js -e OP=$op -e PROFILE=rate -e RATE=200 -e DURATION=1m
  done
  for op in insert submit update; do
    k6run "crud-$op" "$t" k6/scenarios/crud.js -e OP=$op -e PROFILE=rate -e RATE=50 -e DURATION=1m
  done
  for cpus in 1 4; do
    up "$t" "$cpus"
    k6run "ramp-cpu$cpus" "$t" k6/scenarios/mix.js -e PROFILE=ramp
  done
  up "$t" 2
  k6run soak "$t" k6/scenarios/mix.js -e PROFILE=soak -e RATE=50 -e DURATION=${SOAK:-30m}
done
for t in ddcore frappe; do docker compose -f "compose/docker-compose.$t.yml" stop >/dev/null 2>&1; done

python3 scripts/report2.py "$OUT" | tee "$OUT/REPORT-k6.md"
log "done: $OUT"
