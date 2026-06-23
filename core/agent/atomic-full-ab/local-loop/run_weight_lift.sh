#!/usr/bin/env bash
# run_weight_lift.sh [INSTANCE] [N] — the directive's decisive WEIGHT-LIFT experiment, honest by construction.
# Cross-model-capable NO_GATE lift harness (baseline should fail reliably on held-out tasks).
# arm BASE = student model without weight; arm WEIGHT = same student model with ATOMIC_WEIGHTS_FILE injected.
# G2 requires teacher_model != student_model unless explicitly marked experimental.
# N samples per arm, EACH scored on the official SWE-bench harness -> resolution RATE per arm.
# Canonical driver (has weight-injection + seq593). No fake green; the number is the rate.
set -uo pipefail
CALLER_CWD="$(pwd -P)"
HERE="/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"; cd "$HERE"
DRIVER="$HERE/local_atomic_agent.py"
SWE_PYTHON="${SWE_PYTHON:-/opt/homebrew/bin/python3}"

sha256_file(){ shasum -a 256 "$1" | awk '{print $1}'; }
sanitize(){ printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'; }
realpath_file(){ python3 - "$1" <<'PY'
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
}
resolve_path(){
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$CALLER_CWD" "$1" ;;
  esac
}

validate_swebench_python(){
  "$SWE_PYTHON" - <<'PY' >/dev/null 2>&1
import swebench.harness.run_evaluation
PY
}

validate_weights_bank(){
  local weights="$1"
  [ -f "$weights" ] || { echo "weights file not found: $weights" >&2; return 2; }
  local canonical_path=false
  [ "$(realpath_file "$weights")" = "$(realpath_file "$HERE/.corpus/weights.jsonl")" ] && canonical_path=true
  local act_ok
  act_ok=$(python3 - "$weights" <<'PY'
import json, sys
fields = {"preconditions", "transformation", "effects", "cost", "receipt", "fidelity_battery"}
path = sys.argv[1]
rows = []
with open(path) as f:
    for line in f:
        if line.strip():
            rows.append(json.loads(line))
ok = bool(rows) and all(isinstance(r.get("act"), dict) and fields <= set(r["act"]) for r in rows)
print("true" if ok else "false")
PY
)
  if [ "$canonical_path" = true ] && [ "$act_ok" = true ]; then
    echo "true"
    return 0
  fi
  if [ "${ATOMIC_WLIFT_ALLOW_EXPERIMENTAL:-}" = "1" ]; then
    echo "false"
    return 0
  fi
  echo "noncanonical or non-ACT weights bank rejected: $weights" >&2
  return 2
}

TEACHER_MODEL="${ATOMIC_WLIFT_TEACHER_MODEL:-deepseek-v4-pro}"
STUDENT_MODEL="${ATOMIC_WLIFT_STUDENT_MODEL:-${DEEPSEEK_MODEL:-deepseek-v4-pro}}"
BASE_ONLY=false
[ "${ATOMIC_WLIFT_BASE_ONLY:-}" = "1" ] && BASE_ONLY=true
CROSS_MODEL=false
[ "$TEACHER_MODEL" != "$STUDENT_MODEL" ] && CROSS_MODEL=true

if [ "${1:-}" = "--selftest" ]; then
  WEIGHTS="$(resolve_path "${2:-$HERE/.corpus/weights.jsonl}")"
  canonical_act="$(validate_weights_bank "$WEIGHTS")" || exit $?
  weights_sha="$(sha256_file "$WEIGHTS")"
  run_id="wlift_selftest_$(sanitize "$(basename "$WEIGHTS")")_${weights_sha:0:12}"
  echo "canonical_act=$canonical_act"
  echo "run_id=$run_id"
  echo "weights_sha256=$weights_sha"
  echo "teacher_model=$TEACHER_MODEL"
  echo "student_model=$STUDENT_MODEL"
  echo "cross_model=$CROSS_MODEL"
  echo "base_only=$BASE_ONLY"
  echo "swe_python=$SWE_PYTHON"
  if validate_swebench_python; then
    echo "swebench_importable=true"
  else
    echo "swebench_importable=false"
  fi
  echo "summary_fields=base_resolved,weight_resolved,N,lift,weights_sha256,canonical_act,teacher_model,student_model,cross_model,base_only,g2_valid"
  exit 0
fi

ID="${1:-pylint-dev__pylint-7080}"; N="${2:-3}"
WEIGHTS="$(resolve_path "${3:-$HERE/.corpus/weights.jsonl}")"
canonical_act="$(validate_weights_bank "$WEIGHTS")" || exit $?
weights_sha="$(sha256_file "$WEIGHTS")"
if [ "$CROSS_MODEL" != true ] && [ "${ATOMIC_WLIFT_ALLOW_MODEL_EQUAL:-}" != "1" ]; then
  echo "model-equal lift is not G2: teacher_model=$TEACHER_MODEL student_model=$STUDENT_MODEL; set ATOMIC_WLIFT_STUDENT_MODEL to a different model or ATOMIC_WLIFT_ALLOW_MODEL_EQUAL=1 for experimental non-G2" >&2
  exit 2
fi
if ! validate_swebench_python; then
  echo "swebench import failed for SWE_PYTHON=$SWE_PYTHON; official evaluator unavailable, refusing non-G2 run" >&2
  exit 2
fi
TD="$HERE/tasks/SWE-$ID"
PRISTINE="/private/tmp/swe/suite/$ID/pristine"
OUTROOT="$HERE/evidence/WLIFT"; mkdir -p "$OUTROOT"
RUN_MODE="full"
[ "$BASE_ONLY" = true ] && RUN_MODE="base-only"
RUN_ID="${ATOMIC_WLIFT_RUN_ID:-wlift_$(sanitize "$ID")_N${N}_mode_${RUN_MODE}_student_$(sanitize "$STUDENT_MODEL")_${weights_sha:0:12}_$(date -u +%Y%m%dT%H%M%SZ)_$$}"
OUTDIR="$OUTROOT/$RUN_ID"; mkdir -p "$OUTDIR"
LOCKROOT="$OUTROOT/.locks"; mkdir -p "$LOCKROOT"
LOCKDIR="$LOCKROOT/$(sanitize "$ID")_N${N}_mode_${RUN_MODE}_student_$(sanitize "$STUDENT_MODEL")_${weights_sha}.lock"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  echo "weight-lift run already active for instance=$ID N=$N weights_sha256=$weights_sha" >&2
  exit 75
fi
trap 'rm -rf "$LOCKDIR"' EXIT

source /tmp/.atomic_creds.sh
export DEEPSEEK_MODEL="$STUDENT_MODEL" DEEPSEEK_TIMEOUT=120
[ -d "$PRISTINE/.git" ] || { echo "no pristine $PRISTINE"; exit 2; }

run_one(){ # arm sample
  local arm="$1" i="$2"
  local wd="/private/tmp/swe/round/WLIFT/${RUN_ID}_${arm}_${i}"
  rm -rf "$wd"; mkdir -p "$(dirname "$wd")"; cp -R "$PRISTINE" "$wd"
  git -C "$wd" reset --hard -q HEAD; git -C "$wd" clean -fdq
  if [ "$arm" = "weight" ]; then export ATOMIC_WEIGHTS_FILE="$WEIGHTS"; else unset ATOMIC_WEIGHTS_FILE; fi
  local out="$OUTDIR/${arm}_${i}.json"
  python3 "$DRIVER" --workdir "$wd" --task "$TD/PROBLEM.md" --gate NONE --out "$out" --max-steps 60 >/dev/null 2>&1
  local pred="$OUTDIR/pred_${arm}_${i}.jsonl"
  python3 -c "import json;d=json.load(open('$out'));open('$pred','w').write(json.dumps({'instance_id':'$ID','model_name_or_path':'wlift-${arm}','model_patch':d.get('final_diff') or ''})+chr(10))"
  local edits=$(python3 -c "import json;print(json.load(open('$out')).get('edits_applied'))")
  # official score
  "$SWE_PYTHON" -m swebench.harness.run_evaluation --dataset_name princeton-nlp/SWE-bench_Verified \
    --predictions_path "$pred" --run_id "${RUN_ID}_${arm}_${i}" --max_workers 1 --cache_level instance \
    >"$OUTDIR/score_${arm}_${i}.log" 2>&1
  local res=$(grep -aE "Instances resolved:" "$OUTDIR/score_${arm}_${i}.log" | tail -1 | grep -oE "[0-9]+$")
  echo "$arm sample $i: edits=$edits resolved=${res:-?}"
}

echo "=== WEIGHT-LIFT on $ID, N=$N, student_model=$DEEPSEEK_MODEL one-shot NO_GATE ==="
echo "run_id=$RUN_ID"
echo "outdir=$OUTDIR"
echo "weights_sha256=$weights_sha"
echo "canonical_act=$canonical_act"
echo "teacher_model=$TEACHER_MODEL"
echo "student_model=$STUDENT_MODEL"
echo "cross_model=$CROSS_MODEL"
echo "base_only=$BASE_ONLY"
echo "matched weights for this task:"
ATOMIC_WEIGHTS_FILE="$WEIGHTS" python3 -c "
import sys, os, re, json
sys.path.append('$HERE')
import weights_admit
ws = weights_admit.load('$WEIGHTS')
task = open('$TD/PROBLEM.md').read()
task_vsa = weights_admit.encode_vsa_text(task)
for w in ws:
    trig_match = bool(not w.get('trigger') or re.search(w['trigger'], task, re.I))
    w_vsa = w.get('vsa')
    sim = 0.0
    if w_vsa:
        sim = weights_admit.vsa_similarity(task_vsa, w_vsa)
    if trig_match or sim >= 0.15:
        match_info = f'VSA sim={sim:.3f}' if not trig_match else 'regex'
        print('  MATCH:', w['class'], '(proof_n=%s, match via %s)' % (w.get('proof_n'), match_info))
"
base_res=0; weight_res=0
for i in $(seq 1 $N); do r=$(run_one base $i);   echo "$r"; echo "$r" | grep -q "resolved=1" && base_res=$((base_res+1)); done
if [ "$BASE_ONLY" = true ]; then
  echo "=== WEIGHT-LIFT BASELINE PROBE $ID ==="
  echo "BASE   (no weight): $base_res / $N resolved"
  echo "BASE-ONLY probe is not G2; use it only to establish fail-floor before full N lift."
  python3 - "$OUTDIR/g2_summary.json" "$ID" "$N" "$base_res" "-1" "$weights_sha" "$canonical_act" "$RUN_ID" "$TEACHER_MODEL" "$STUDENT_MODEL" "$CROSS_MODEL" "$BASE_ONLY" <<'PY'
import json, sys
out, instance, n, base, weight, weights_sha, canonical_act, run_id, teacher_model, student_model, cross_model, base_only = sys.argv[1:]
n = int(n); base = int(base); base_only_bool = base_only == "true"
weight_value = None if base_only_bool else int(weight)
data = {
    "instance": instance,
    "N": n,
    "base_resolved": base,
    "weight_resolved": weight_value,
    "lift": None if base_only_bool else weight_value - base,
    "weights_sha256": weights_sha,
    "canonical_act": canonical_act == "true",
    "run_id": run_id,
    "teacher_model": teacher_model,
    "student_model": student_model,
    "cross_model": cross_model == "true",
    "base_only": base_only_bool,
    "g2_valid": False,
}
open(out, "w").write(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
  echo "G2 summary: $OUTDIR/g2_summary.json"
  exit 0
fi
for i in $(seq 1 $N); do r=$(run_one weight $i); echo "$r"; echo "$r" | grep -q "resolved=1" && weight_res=$((weight_res+1)); done
echo "=== WEIGHT-LIFT RESULT $ID ==="
echo "BASE   (no weight): $base_res / $N resolved"
echo "WEIGHT (injected):  $weight_res / $N resolved"
echo "LIFT = $((weight_res - base_res)) / $N  (positive => weight lifts the model on this class, by number)"
python3 - "$OUTDIR/g2_summary.json" "$ID" "$N" "$base_res" "$weight_res" "$weights_sha" "$canonical_act" "$RUN_ID" "$TEACHER_MODEL" "$STUDENT_MODEL" "$CROSS_MODEL" "$BASE_ONLY" <<'PY'
import json, sys
out, instance, n, base, weight, weights_sha, canonical_act, run_id, teacher_model, student_model, cross_model, base_only = sys.argv[1:]
n = int(n); base = int(base); weight = int(weight); base_only_bool = base_only == "true"
data = {
    "instance": instance,
    "N": n,
    "base_resolved": base,
    "weight_resolved": weight,
    "lift": weight - base,
    "weights_sha256": weights_sha,
    "canonical_act": canonical_act == "true",
    "run_id": run_id,
    "teacher_model": teacher_model,
    "student_model": student_model,
    "cross_model": cross_model == "true",
    "base_only": base_only_bool,
    "g2_valid": (canonical_act == "true") and (cross_model == "true") and not base_only_bool,
}
open(out, "w").write(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
echo "G2 summary: $OUTDIR/g2_summary.json"
