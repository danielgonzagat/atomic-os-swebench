#!/usr/bin/env bash
# run_weight_lift.sh [INSTANCE] [N] — the directive's decisive WEIGHT-LIFT experiment, honest by construction.
# Same model (DeepSeek V4 Pro), NO_GATE one-shot (a reliably-FAILING baseline on pylint-7080).
# arm BASE = no weight; arm WEIGHT = ATOMIC_WEIGHTS_FILE injected. Weight is the ONLY variable.
# N samples per arm, EACH scored on the official SWE-bench harness -> resolution RATE per arm.
# Canonical driver (has weight-injection + seq593). No fake green; the number is the rate.
set -uo pipefail
HERE="/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"; cd "$HERE"
ID="${1:-pylint-dev__pylint-7080}"; N="${2:-3}"
DRIVER="$HERE/local_atomic_agent.py"
WEIGHTS="${3:-$HERE/.corpus/weights.jsonl}"
TD="$HERE/tasks/SWE-$ID"
PRISTINE="/private/tmp/swe/suite/$ID/pristine"
OUTDIR="$HERE/evidence/WLIFT"; mkdir -p "$OUTDIR"
source /tmp/.atomic_creds.sh
export DEEPSEEK_MODEL=deepseek-v4-pro DEEPSEEK_TIMEOUT=120
[ -d "$PRISTINE/.git" ] || { echo "no pristine $PRISTINE"; exit 2; }

run_one(){ # arm sample
  local arm="$1" i="$2"
  local wd="/private/tmp/swe/round/WLIFT/${ID}_${arm}_${i}"
  rm -rf "$wd"; mkdir -p "$(dirname "$wd")"; cp -R "$PRISTINE" "$wd"
  git -C "$wd" reset --hard -q HEAD; git -C "$wd" clean -fdq
  if [ "$arm" = "weight" ]; then export ATOMIC_WEIGHTS_FILE="$WEIGHTS"; else unset ATOMIC_WEIGHTS_FILE; fi
  local out="$OUTDIR/${arm}_${i}.json"
  python3 "$DRIVER" --workdir "$wd" --task "$TD/PROBLEM.md" --gate NONE --out "$out" --max-steps 60 >/dev/null 2>&1
  local pred="$OUTDIR/pred_${arm}_${i}.jsonl"
  python3 -c "import json;d=json.load(open('$out'));open('$pred','w').write(json.dumps({'instance_id':'$ID','model_name_or_path':'wlift-${arm}','model_patch':d.get('final_diff') or ''})+chr(10))"
  local edits=$(python3 -c "import json;print(json.load(open('$out')).get('edits_applied'))")
  # official score
  python3 -m swebench.harness.run_evaluation --dataset_name princeton-nlp/SWE-bench_Verified \
    --predictions_path "$pred" --run_id "wlift_${ID//[^A-Za-z0-9]/_}_${arm}_${i}" --max_workers 1 --cache_level instance \
    >"$OUTDIR/score_${arm}_${i}.log" 2>&1
  local res=$(grep -aE "Instances resolved:" "$OUTDIR/score_${arm}_${i}.log" | tail -1 | grep -oE "[0-9]+$")
  echo "$arm sample $i: edits=$edits resolved=${res:-?}"
}

echo "=== WEIGHT-LIFT on $ID, N=$N, model=$DEEPSEEK_MODEL one-shot NO_GATE ==="
echo "matched weights for this task:"
ATOMIC_WEIGHTS_FILE="$WEIGHTS" python3 -c "
import json,re,os
ws=[json.loads(l) for l in open('$WEIGHTS') if l.strip()]
task=open('$TD/PROBLEM.md').read().lower()
for w in ws:
    if re.search(w.get('trigger',''), task): print('  MATCH:', w['class'], '(proof_n=%s)'%w.get('proof_n'))
"
base_res=0; weight_res=0
for i in $(seq 1 $N); do r=$(run_one base $i);   echo "$r"; echo "$r" | grep -q "resolved=1" && base_res=$((base_res+1)); done
for i in $(seq 1 $N); do r=$(run_one weight $i); echo "$r"; echo "$r" | grep -q "resolved=1" && weight_res=$((weight_res+1)); done
echo "=== WEIGHT-LIFT RESULT $ID ==="
echo "BASE   (no weight): $base_res / $N resolved"
echo "WEIGHT (injected):  $weight_res / $N resolved"
echo "LIFT = $((weight_res - base_res)) / $N  (positive => weight lifts the model on this class, by number)"
