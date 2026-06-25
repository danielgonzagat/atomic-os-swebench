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
  python3 - "$SWE_PYTHON" "$SWEBENCH_IMPORT_TIMEOUT_SECONDS" <<'PY' >/dev/null 2>&1
import subprocess, sys
swe_python, timeout = sys.argv[1], int(sys.argv[2])
subprocess.check_call(
    [swe_python, "-c", "import swebench.harness.run_evaluation"],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    timeout=timeout,
)
PY
}

validate_docker_api(){
  python3 - "$DOCKER_TIMEOUT_SECONDS" <<'PY' >/dev/null 2>&1
import subprocess, sys
timeout = int(sys.argv[1])
subprocess.check_output(["docker", "version", "--format", "{{.Server.Version}}"], stderr=subprocess.STDOUT, text=True, timeout=timeout)
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

matched_weight_fidelity_report(){
  local weights="$1" task_file="$2"
  python3 - "$weights" "$task_file" <<'PY'
import json, re, sys
weights_path, task_file = sys.argv[1:]
task = open(task_file).read()
matched = []
unproven = []
with open(weights_path) as f:
    rows = [json.loads(line) for line in f if line.strip()]
for weight in rows:
    trigger = weight.get("trigger") or ""
    try:
        trigger_match = bool((not trigger) or re.search(trigger, task, re.I))
    except re.error:
        trigger_match = False
    if trigger_match:
        cls = str(weight.get("class") or "UNKNOWN")
        matched.append(cls)
        act = weight.get("act") if isinstance(weight.get("act"), dict) else {}
        battery = weight.get("fidelity_battery") or act.get("fidelity_battery") or weight.get("instances") or []
        if not isinstance(battery, list) or not battery:
            unproven.append(cls)
print("matched_weight_fidelity_ok=" + ("true" if not unproven else "false"))
print("matched_weight_classes=" + ",".join(matched))
print("unproven_matched_weight_classes=" + ",".join(unproven))
PY
}

TEACHER_MODEL="${ATOMIC_WLIFT_TEACHER_MODEL:-deepseek-v4-pro}"
STUDENT_MODEL="${ATOMIC_WLIFT_STUDENT_MODEL:-${DEEPSEEK_MODEL:-deepseek-v4-pro}}"
BASE_ONLY=false
[ "${ATOMIC_WLIFT_BASE_ONLY:-}" = "1" ] && BASE_ONLY=true
SAMPLE_TIMEOUT_SECONDS="${ATOMIC_WLIFT_SAMPLE_TIMEOUT_SECONDS:-600}"
SCORE_TIMEOUT_SECONDS="${ATOMIC_WLIFT_SCORE_TIMEOUT_SECONDS:-900}"
SCORE_ATTEMPTS="${ATOMIC_WLIFT_SCORE_ATTEMPTS:-2}"
MIN_FREE_KB="${ATOMIC_WLIFT_MIN_FREE_KB:-2097152}"
DOCKER_TIMEOUT_SECONDS="${ATOMIC_WLIFT_DOCKER_TIMEOUT_SECONDS:-20}"
SWEBENCH_IMPORT_TIMEOUT_SECONDS="${ATOMIC_WLIFT_SWEBENCH_IMPORT_TIMEOUT_SECONDS:-120}"
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
  echo "sample_timeout_seconds=$SAMPLE_TIMEOUT_SECONDS"
  echo "score_timeout_seconds=$SCORE_TIMEOUT_SECONDS"
  echo "score_attempts=$SCORE_ATTEMPTS"
  echo "min_free_kb=$MIN_FREE_KB"
  echo "docker_timeout_seconds=$DOCKER_TIMEOUT_SECONDS"
  echo "swebench_import_timeout_seconds=$SWEBENCH_IMPORT_TIMEOUT_SECONDS"
  echo "swe_python=$SWE_PYTHON"
  if validate_swebench_python; then
    echo "swebench_importable=true"
  else
    echo "swebench_importable=false"
  fi
  echo "summary_fields=base_resolved,weight_resolved,N,lift,weights_sha256,canonical_act,teacher_model,student_model,cross_model,base_only,sample_timeouts,score_failures,goldilocks_baseline,fail_floor_positive_lift,matched_weight_fidelity_ok,unproven_matched_weight_classes,g2_valid"
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
available_kb=$(df -k /private/tmp | awk 'NR==2 {print $4}')
if [ "${available_kb:-0}" -lt "$MIN_FREE_KB" ]; then
  echo "insufficient free space for WLIFT scratch: available_kb=${available_kb:-0} required_kb=$MIN_FREE_KB path=/private/tmp" >&2
  exit 2
fi
TD="$HERE/tasks/SWE-$ID"
[ -f "$TD/PROBLEM.md" ] || { echo "task problem not found: $TD/PROBLEM.md" >&2; exit 2; }
matched_report="$(matched_weight_fidelity_report "$WEIGHTS" "$TD/PROBLEM.md")"
matched_weight_fidelity_ok="$(printf '%s\n' "$matched_report" | awk -F= '$1=="matched_weight_fidelity_ok" {print $2}')"
unproven_matched_weight_classes="$(printf '%s\n' "$matched_report" | awk -F= '$1=="unproven_matched_weight_classes" {print $2}')"
if [ "$BASE_ONLY" != true ] && [ "$matched_weight_fidelity_ok" != true ] && [ "${ATOMIC_WLIFT_ALLOW_UNPROVEN_MATCHED_WEIGHTS:-}" != "1" ]; then
  echo "matched weights lack proof-carrying fidelity battery: ${unproven_matched_weight_classes:-unknown}; refusing full G2 run" >&2
  exit 2
fi
if ! validate_swebench_python; then
  echo "swebench import failed for SWE_PYTHON=$SWE_PYTHON; official evaluator unavailable, refusing non-G2 run" >&2
  exit 2
fi
if ! validate_docker_api; then
  echo "docker API unavailable for official SWE-bench scoring within ${DOCKER_TIMEOUT_SECONDS}s; refusing non-G2 run" >&2
  exit 2
fi
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
  local out="$OUTDIR/${arm}_${i}.json"
  if ! rm -rf "$wd" || ! mkdir -p "$(dirname "$wd")" || ! cp -R "$PRISTINE" "$wd"; then
    python3 - "$out" <<'PY'
import json, sys
with open(sys.argv[1], "w") as f:
    json.dump({"final_diff": "", "edits_applied": 0, "error": "scratch_setup_failed"}, f)
PY
    echo "$arm sample $i: edits=0 resolved=? timeout=0 score_timeout=0 score_bad=1 setup_failed=1"
    return
  fi
  git -C "$wd" reset --hard -q HEAD; git -C "$wd" clean -fdq
  if [ "$arm" = "weight" ]; then export ATOMIC_WEIGHTS_FILE="$WEIGHTS"; else unset ATOMIC_WEIGHTS_FILE; fi
  local driver_status=0 timeout_hit=0
  python3 - "$SAMPLE_TIMEOUT_SECONDS" "$DRIVER" "$wd" "$TD/PROBLEM.md" "$out" <<'PY' >/dev/null 2>&1
import json, os, subprocess, sys

timeout = int(sys.argv[1])
driver, wd, task, out = sys.argv[2:]
cmd = [
    sys.executable,
    driver,
    "--workdir", wd,
    "--task", task,
    "--gate", "NONE",
    "--out", out,
    "--max-steps", "60",
]
try:
    completed = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=timeout)
except subprocess.TimeoutExpired:
    with open(out, "w") as f:
        json.dump({"final_diff": "", "edits_applied": 0, "error": "agent_timeout", "timeout_seconds": timeout}, f)
    sys.exit(124)
if completed.returncode != 0 and not os.path.exists(out):
    with open(out, "w") as f:
        json.dump({"final_diff": "", "edits_applied": 0, "error": "agent_exit", "exit_code": completed.returncode}, f)
sys.exit(completed.returncode)
PY
  driver_status=$?
  [ "$driver_status" -eq 124 ] && timeout_hit=1
  [ -s "$out" ] || python3 - "$out" "$driver_status" <<'PY'
import json, sys
out, status = sys.argv[1:]
with open(out, "w") as f:
    json.dump({"final_diff": "", "edits_applied": 0, "error": "missing_agent_output", "exit_code": int(status)}, f)
PY
  local pred="$OUTDIR/pred_${arm}_${i}.jsonl"
  python3 -c "import json;d=json.load(open('$out'));open('$pred','w').write(json.dumps({'instance_id':'$ID','model_name_or_path':'wlift-${arm}','model_patch':d.get('final_diff') or ''})+chr(10))"
  local edits=$(python3 -c "import json;print(json.load(open('$out')).get('edits_applied') or 0)")
  # official score
  local score_log="$OUTDIR/score_${arm}_${i}.log"
  local score_status=0 score_timeout=0
  python3 - "$SCORE_TIMEOUT_SECONDS" "$SCORE_ATTEMPTS" "$score_log" "$SWE_PYTHON" "$pred" "${RUN_ID}_${arm}_${i}" <<'PY' >/dev/null 2>&1
import subprocess, sys, time

timeout = int(sys.argv[1])
attempts = int(sys.argv[2])
score_log, swe_python, pred, run_id = sys.argv[3:]
cmd = [
    swe_python,
    "-m", "swebench.harness.run_evaluation",
    "--dataset_name", "princeton-nlp/SWE-bench_Verified",
    "--predictions_path", pred,
    "--run_id", run_id,
    "--max_workers", "1",
    "--cache_level", "instance",
]
last_status = 1
with open(score_log, "w") as log:
    for attempt in range(1, attempts + 1):
        if attempt > 1:
            log.write(f"\nSWE_SCORE_RETRY attempt={attempt}/{attempts}\n")
            log.flush()
            time.sleep(5)
        attempt_cmd = list(cmd)
        if attempt > 1:
            attempt_cmd[attempt_cmd.index("--run_id") + 1] = f"{run_id}_retry{attempt}"
        try:
            completed = subprocess.run(attempt_cmd, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
        except subprocess.TimeoutExpired:
            log.write(f"\nSWE_SCORE_TIMEOUT seconds={timeout} attempt={attempt}/{attempts}\n")
            log.flush()
            last_status = 124
            continue
        last_status = completed.returncode
        log.flush()
        if completed.returncode == 0:
            sys.exit(0)
    sys.exit(last_status)
PY
  score_status=$?
  [ "$score_status" -eq 124 ] && score_timeout=1
  local res=$(grep -aE "Instances resolved:" "$score_log" | tail -1 | grep -oE "[0-9]+$")
  local score_bad=0
  [ -z "${res:-}" ] && score_bad=1
  rm -rf "$wd"
  echo "$arm sample $i: edits=$edits resolved=${res:-?} timeout=$timeout_hit score_timeout=$score_timeout score_bad=$score_bad"
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
echo "matched_weight_fidelity_ok=${matched_weight_fidelity_ok:-not_checked}"
echo "unproven_matched_weight_classes=${unproven_matched_weight_classes:-}"
echo "sample_timeout_seconds=$SAMPLE_TIMEOUT_SECONDS"
echo "score_timeout_seconds=$SCORE_TIMEOUT_SECONDS"
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
base_res=0; weight_res=0; base_timeouts=0; weight_timeouts=0; base_score_failures=0; weight_score_failures=0
for i in $(seq 1 $N); do
  r=$(run_one base $i); echo "$r"
  echo "$r" | grep -q "resolved=1" && base_res=$((base_res+1))
  echo "$r" | grep -q " timeout=1" && base_timeouts=$((base_timeouts+1))
  echo "$r" | grep -q " score_bad=1" && base_score_failures=$((base_score_failures+1))
done
if [ "$BASE_ONLY" = true ]; then
  echo "=== WEIGHT-LIFT BASELINE PROBE $ID ==="
  echo "BASE   (no weight): $base_res / $N resolved"
  echo "BASE TIMEOUTS: $base_timeouts / $N"
  echo "BASE SCORE FAILURES: $base_score_failures / $N"
  echo "BASE-ONLY probe is not G2; use it only to establish fail-floor before full N lift."
  python3 - "$OUTDIR/g2_summary.json" "$ID" "$N" "$base_res" "-1" "$base_timeouts" "$base_score_failures" "$weights_sha" "$canonical_act" "$RUN_ID" "$TEACHER_MODEL" "$STUDENT_MODEL" "$CROSS_MODEL" "$BASE_ONLY" "$matched_weight_fidelity_ok" "$unproven_matched_weight_classes" <<'PY'
import json, sys
out, instance, n, base, weight, sample_timeouts, score_failures, weights_sha, canonical_act, run_id, teacher_model, student_model, cross_model, base_only, matched_weight_fidelity_ok, unproven_matched_weight_classes = sys.argv[1:]
n = int(n); base = int(base); sample_timeouts = int(sample_timeouts); score_failures = int(score_failures); base_only_bool = base_only == "true"
weight_value = None if base_only_bool else int(weight)
data = {
    "instance": instance,
    "N": n,
    "base_resolved": base,
    "weight_resolved": weight_value,
    "lift": None if base_only_bool else weight_value - base,
    "sample_timeouts": sample_timeouts,
    "score_failures": score_failures,
    "goldilocks_baseline": 0 < base < n,
    "fail_floor_positive_lift": False,
    "weights_sha256": weights_sha,
    "canonical_act": canonical_act == "true",
    "run_id": run_id,
    "teacher_model": teacher_model,
    "student_model": student_model,
    "cross_model": cross_model == "true",
    "base_only": base_only_bool,
    "matched_weight_fidelity_ok": matched_weight_fidelity_ok == "true",
    "unproven_matched_weight_classes": [c for c in unproven_matched_weight_classes.split(",") if c],
    "g2_valid": False,
}
open(out, "w").write(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
  echo "G2 summary: $OUTDIR/g2_summary.json"
  exit 0
fi
for i in $(seq 1 $N); do
  r=$(run_one weight $i); echo "$r"
  echo "$r" | grep -q "resolved=1" && weight_res=$((weight_res+1))
  echo "$r" | grep -q " timeout=1" && weight_timeouts=$((weight_timeouts+1))
  echo "$r" | grep -q " score_bad=1" && weight_score_failures=$((weight_score_failures+1))
done
echo "=== WEIGHT-LIFT RESULT $ID ==="
echo "BASE   (no weight): $base_res / $N resolved"
echo "WEIGHT (injected):  $weight_res / $N resolved"
echo "SAMPLE TIMEOUTS: $((base_timeouts + weight_timeouts)) / $((N * 2))"
echo "SCORE FAILURES: $((base_score_failures + weight_score_failures)) / $((N * 2))"
echo "LIFT = $((weight_res - base_res)) / $N  (positive => weight lifts the model on this class, by number)"
python3 - "$OUTDIR/g2_summary.json" "$ID" "$N" "$base_res" "$weight_res" "$base_timeouts" "$weight_timeouts" "$base_score_failures" "$weight_score_failures" "$weights_sha" "$canonical_act" "$RUN_ID" "$TEACHER_MODEL" "$STUDENT_MODEL" "$CROSS_MODEL" "$BASE_ONLY" "$matched_weight_fidelity_ok" "$unproven_matched_weight_classes" <<'PY'
import json, sys
out, instance, n, base, weight, base_timeouts, weight_timeouts, base_score_failures, weight_score_failures, weights_sha, canonical_act, run_id, teacher_model, student_model, cross_model, base_only, matched_weight_fidelity_ok, unproven_matched_weight_classes = sys.argv[1:]
n = int(n); base = int(base); weight = int(weight); sample_timeouts = int(base_timeouts) + int(weight_timeouts); score_failures = int(base_score_failures) + int(weight_score_failures); base_only_bool = base_only == "true"
goldilocks_baseline = 0 < base < n
fail_floor_positive_lift = base == 0 and weight > base
matched_fidelity_ok = matched_weight_fidelity_ok == "true"
integrity_ok = (
    canonical_act == "true"
    and cross_model == "true"
    and not base_only_bool
    and sample_timeouts == 0
    and score_failures == 0
    and matched_fidelity_ok
)
data = {
    "instance": instance,
    "N": n,
    "base_resolved": base,
    "weight_resolved": weight,
    "lift": weight - base,
    "sample_timeouts": sample_timeouts,
    "score_failures": score_failures,
    "goldilocks_baseline": goldilocks_baseline,
    "fail_floor_positive_lift": fail_floor_positive_lift,
    "weights_sha256": weights_sha,
    "canonical_act": canonical_act == "true",
    "run_id": run_id,
    "teacher_model": teacher_model,
    "student_model": student_model,
    "cross_model": cross_model == "true",
    "base_only": base_only_bool,
    "matched_weight_fidelity_ok": matched_fidelity_ok,
    "unproven_matched_weight_classes": [c for c in unproven_matched_weight_classes.split(",") if c],
    "g2_valid": integrity_ok and (goldilocks_baseline or fail_floor_positive_lift),
}
open(out, "w").write(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
echo "G2 summary: $OUTDIR/g2_summary.json"
