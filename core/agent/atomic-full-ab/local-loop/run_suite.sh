#!/usr/bin/env bash
# run_suite.sh — fire DeepSeek-atomic on ALL 5 suite instances, one-shot, instrumented.
# Usage: ./run_suite.sh <round_tag>
set -uo pipefail
RTAG="${1:-Rxxx}"
HERE="$(cd "$(dirname "$0")" && pwd)"
IDS=(psf__requests-1921 pytest-dev__pytest-7982 pytest-dev__pytest-5262 pylint-dev__pylint-7080 pallets__flask-5014)
for IID in "${IDS[@]}"; do
  echo "================ ${RTAG} ${IID} $(date +%T) ================"
  bash "${HERE}/run_atomic_round.sh" "$IID" "$RTAG" 2>&1 | grep -E 'ATOMIC DONE|round|NO ' || true
done
echo "================ SUITE ${RTAG} COMPLETE $(date +%T) ================"
