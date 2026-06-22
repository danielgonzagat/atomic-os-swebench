#!/usr/bin/env bash
# run_atomic_round.sh — fire the DeepSeek-atomic agent on ONE instance, one-shot (NO_GATE),
# against a FRESH workdir copied from the pristine checkout. Captures result JSON + transcript.
# Usage: ./run_atomic_round.sh <full_instance_id> <round_tag>
#   e.g. ./run_atomic_round.sh psf__requests-1921 R022
set -euo pipefail
IID="$1"; RTAG="${2:-Rxxx}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PRISTINE="/tmp/swe/suite/${IID}/pristine"
TASK="${HERE}/tasks/SWE-${IID}/PROBLEM.md"
OUTDIR="${HERE}/evidence/${RTAG}"
WD="/tmp/swe/round/${RTAG}/${IID}/atomic"

[ -d "$PRISTINE/.git" ] || { echo "NO PRISTINE: $PRISTINE" >&2; exit 2; }
[ -f "$TASK" ] || { echo "NO TASK: $TASK" >&2; exit 2; }
mkdir -p "$OUTDIR" "$(dirname "$WD")"
rm -rf "$WD"; cp -R "$PRISTINE" "$WD"
# clean working tree so git diff HEAD reflects ONLY the agent's edits
git -C "$WD" reset --hard --quiet HEAD
git -C "$WD" clean -fdq

OUT="${OUTDIR}/${IID}__atomic.json"
echo "[round ${RTAG}] ${IID} -> ${OUT}" >&2
python3 "${HERE}/local_atomic_agent.py" \
  --workdir "$WD" --task "$TASK" --gate NONE --out "$OUT" --max-steps 60
echo "WORKDIR=$WD" >&2
echo "DIFF:" >&2
git -C "$WD" diff HEAD >&2 || true
