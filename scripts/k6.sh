#!/usr/bin/env bash
# k6 with the target's token, sampling the stack's CPU/memory while it runs.
#   [NAME=label] scripts/k6.sh <ddcore|frappe> <script> [k6 args…]
# Writes results/k6/<label>-<target>-<time>.json (+ .stats.csv); OUTDIR overrides the folder.
set -euo pipefail
cd "$(dirname "$0")/.."
T=${1:?target}; S=${2:?script}; shift 2
set -a; . ./.env.bench; set +a
V="TOKEN_$(echo "$T" | tr a-z A-Z)"
OUTDIR=${OUTDIR:-results/k6}
mkdir -p "$OUTDIR"
base="$OUTDIR/${NAME:-$(basename "$S" .js)}-$T-$(date +%H%M%S)"
docker stats --format '{{.Name}},{{.MemUsage}},{{.CPUPerc}}' \
  $(docker ps -q --filter "label=com.docker.compose.project=bench-$T") > "$base.stats.csv" &
sp=$!
trap 'kill $sp 2>/dev/null || true' EXIT
k6 run -e TARGET="$T" -e TOKEN="${!V}" --summary-export "$base.json" "$S" "$@"
