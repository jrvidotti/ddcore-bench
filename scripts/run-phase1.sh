#!/usr/bin/env bash
# Runs Phase 1 against both targets, one stack up at a time, then writes the report.
#   scripts/run-phase1.sh [out-dir]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-results/$(date +%Y-%m-%d)-$(git rev-parse --short HEAD 2>/dev/null || echo nogit)}
mkdir -p "$OUT"
cp results/latest/boot-*.json "$OUT/" 2>/dev/null || true
{
  echo "host: $(uname -srm), $(sysctl -n hw.ncpu 2>/dev/null || nproc) cpus"
  echo "docker: $(docker version -f '{{.Server.Version}}')"
  echo "ddcore: ${DDCORE_VERSION:-0.21.10}"
  echo "frappe: $(docker run --rm --entrypoint cat ddcore-bench/frappe:latest /home/frappe/frappe-bench/apps/frappe/frappe/__init__.py | grep -Eo '__version__ = .*')"
  echo "limits: app cpus=${APP_CPUS:-2} mem=${APP_MEM:-2g}; db cpus=${DB_CPUS:-2} mem=${DB_MEM:-2g}"
} > "$OUT/versions.txt"

for t in ddcore frappe; do
  for o in ddcore frappe; do docker compose -f compose/docker-compose.$o.yml stop >/dev/null 2>&1 || true; done
  docker compose -f compose/docker-compose.$t.yml start >/dev/null
  if [ "$t" = ddcore ]; then url=http://localhost:8101/readyz; else url=http://localhost:8102/api/method/ping; fi
  until curl -fsS -o /dev/null "$url" 2>/dev/null; do sleep 1; done
  scripts/phase1.sh "$t" "$OUT"
done
python3 scripts/report.py "$OUT" | tee "$OUT/REPORT.md"
