#!/usr/bin/env bash
# run_round.sh <instance_id> <rtag> <img_grep>
# Generic Atomic-only gate-ON round, CANONICAL driver (seq593+ live). Official scoring after.
set -euo pipefail
ID="$1"; RTAG="$2"; IMGGREP="$3"
HERE="/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"
AGENT_PYTHON="${AGENT_PYTHON:-/opt/homebrew/bin/python3}"
SWE_PYTHON="${SWE_PYTHON:-/opt/homebrew/bin/python3}"
cd "$HERE"
source /tmp/.atomic_creds.sh 2>/dev/null || true
export DEEPSEEK_MODEL=deepseek-v4-pro
export DEEPSEEK_TIMEOUT="${DEEPSEEK_TIMEOUT:-120}"
export DEEPSEEK_TOTAL_TIMEOUT="${DEEPSEEK_TOTAL_TIMEOUT:-180}"
# CLASS-ROUND-WEIGHTS-ENABLED-BY-DEFAULT: the canonical Atomic A/B loop must run with
# the proof-carrying learned-weight bank connected. Respect explicit caller overrides:
# an already-set ATOMIC_WEIGHTS_FILE can point elsewhere or be intentionally empty.
if [ -z "${ATOMIC_WEIGHTS_FILE+x}" ] && [ -s "$HERE/.corpus/weights.jsonl" ]; then
  export ATOMIC_WEIGHTS_FILE="$HERE/.corpus/weights.jsonl"
fi

TD="$HERE/tasks/SWE-$ID"
PRISTINE="/private/tmp/swe/suite/$ID/pristine"
WD="/private/tmp/swe/round/$RTAG/$ID/atomic"
CONT="$(echo ${ID}_${RTAG}_atomic | tr -c 'A-Za-z0-9_' '_')"
OUTDIR="$HERE/evidence/$RTAG"
OUT="$OUTDIR/${ID}__atomic_gateON.json"
PRED="$OUTDIR/${ID}__atomic_gateON.pred.jsonl"
LOG="$OUTDIR/${ID}__atomic_gateON.log"

mkdir -p "$OUTDIR" "$(dirname "$WD")"
[ -d "$PRISTINE/.git" ] || { echo "$RTAG FATAL: no pristine $PRISTINE"; exit 2; }
[ -f "$TD/PROBLEM.md" ] || { echo "$RTAG FATAL: no task $TD/PROBLEM.md"; exit 2; }
rm -rf "$WD"; cp -R "$PRISTINE" "$WD"
git -C "$WD" reset --hard -q HEAD; git -C "$WD" clean -fdq

IMG=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -iE "$IMGGREP" | head -1 || true)
[ -z "$IMG" ] && { echo "$RTAG FATAL: no image matching $IMGGREP"; exit 9; }
docker rm -f "$CONT" >/dev/null 2>&1 || true
docker run -d --name "$CONT" "$IMG" tail -f /dev/null >/dev/null 2>&1
echo "$RTAG ATOMIC(gate-ON) $ID START $(date +%H:%M:%S) img=$IMG cont=$CONT" | tee "$LOG"

if ! "$AGENT_PYTHON" "$HERE/local_atomic_agent.py" --workdir "$WD" --task "$TD/PROBLEM.md" \
  --gate "env SWE_CONTAINER=$CONT SWE_P2P_SAMPLE=8 bash /private/tmp/swe/iso-driver-claude/swe_gate_iso.sh $WD $TD" \
  --out "$OUT" --max-steps 70 >>"$LOG" 2>&1; then
  echo "$RTAG FATAL: agent failed before receipt $(date +%H:%M:%S)" | tee -a "$LOG"
  docker rm -f "$CONT" >/dev/null 2>&1 || true
  exit 11
fi
[ -s "$OUT" ] || { echo "$RTAG FATAL: agent did not write receipt $OUT" | tee -a "$LOG"; docker rm -f "$CONT" >/dev/null 2>&1 || true; exit 12; }
echo "$RTAG agent done $(date +%H:%M:%S)" | tee -a "$LOG"

"$AGENT_PYTHON" -c "
import json,re
d=json.load(open('$OUT'))
diff=d.get('final_diff') or ''
open('$PRED','w').write(json.dumps({'instance_id':'$ID','model_name_or_path':'atomic-gateON','model_patch':diff})+chr(10))
print('$RTAG gate_pass',d.get('gate_pass'),'edits',d.get('edits_applied'),'steps',d.get('steps'),'reads',d.get('reads'),'tokens',d.get('tokens'),'diff_lines',d.get('diff_lines'),'files',sorted(set(re.findall(r'\+\+\+ b/(\S+)',diff))))
" | tee -a "$LOG"

echo "$RTAG OFFICIAL scoring START $(date +%H:%M:%S)" | tee -a "$LOG"
"$SWE_PYTHON" -m swebench.harness.run_evaluation --dataset_name princeton-nlp/SWE-bench_Verified \
  --predictions_path "$PRED" --run_id ${RTAG}_$(echo $ID|tr -c 'A-Za-z0-9' '_')_atomic --max_workers 1 --cache_level instance \
  >>"$LOG" 2>&1
echo "$RTAG OFFICIAL: $(grep -iE 'Instances resolved|Instances unresolved' "$LOG" | tail -2)" | tee -a "$LOG"
docker rm -f "$CONT" >/dev/null 2>&1 || true
echo "$RTAG DONE $(date +%H:%M:%S)" | tee -a "$LOG"
