#!/usr/bin/env bash
# Blocks until the target's app answers (a started container is not a listening server).
#   scripts/wait-ready.sh <ddcore|frappe> [timeout-seconds]
set -euo pipefail
T=${1:?target}; MAX=${2:-300}
if [ "$T" = ddcore ]; then url=http://localhost:8101/readyz; else url=http://localhost:8102/api/method/ping; fi
start=$(date +%s)
until curl -fsS -o /dev/null "$url" 2>/dev/null; do
  if (( $(date +%s) - start > MAX )); then echo "[$T] not ready after ${MAX}s ($url)" >&2; exit 1; fi
  sleep 1
done
# one more beat: the proxy port can open a moment before every worker accepts
sleep 2
echo "[$T] ready in $(( $(date +%s) - start ))s"
