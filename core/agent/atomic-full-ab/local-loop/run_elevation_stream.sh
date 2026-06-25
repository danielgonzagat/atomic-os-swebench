#!/usr/bin/env bash
# run_elevation_stream.sh — distinct-task Elevation stream for the finetunable substrate.
#
# Metric: DeepSeek V4 Pro with the accumulated canonical ACT substrate is measured only
# on official SWE-Bench Pro tasks, against a paired frozen frontier baseline on the same
# task ids. Verified/WLIFT/within-task efficiency is diagnostic only, not Elevação.
# This replaces recurrence-style WLIFT as the north metric; no synthetic recurrence.
set -uo pipefail

CALLER_CWD="$(pwd -P)"
HERE="/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"; cd "$HERE"
DRIVER="$HERE/local_atomic_agent.py"
SWE_PYTHON="${SWE_PYTHON:-/opt/homebrew/bin/python3}"
MODEL="deepseek-v4-pro"
BENCHMARK_SUITE="${ATOMIC_ELEVATION_BENCHMARK_SUITE:-swe_bench_pro}"
DATASET_NAME="${ATOMIC_ELEVATION_DATASET_NAME:-ScaleAI/SWE-bench_Pro}"
TASKROOT="${ATOMIC_ELEVATION_TASK_ROOT:-$HERE/tasks}"
SUITEROOT="${ATOMIC_ELEVATION_SUITE_ROOT:-${ATOMIC_SWE_SUITE_ROOT:-/tmp/swe/suite}}"

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
  python3 - "$SWE_PYTHON" "${ATOMIC_ELEVATION_IMPORT_TIMEOUT_SECONDS:-20}" <<'PY' >/dev/null 2>&1
import subprocess, sys
swe_python, timeout = sys.argv[1], int(sys.argv[2])
subprocess.check_call([swe_python, "-c", "import swebench.harness.run_evaluation"], timeout=timeout)
PY
}

validate_docker_api(){
  python3 - "${ATOMIC_ELEVATION_DOCKER_TIMEOUT_SECONDS:-20}" <<'PY' >/dev/null 2>&1
import subprocess, sys
timeout = int(sys.argv[1])
subprocess.check_output(["docker", "version", "--format", "{{.Server.Version}}"], stderr=subprocess.STDOUT, text=True, timeout=timeout)
PY
}

is_official_benchmark(){
  [ "$BENCHMARK_SUITE" = "swe_bench_pro" ] && [ "$DATASET_NAME" = "ScaleAI/SWE-bench_Pro" ]
}

task_problem_path(){
  printf '%s/SWE-%s/PROBLEM.md\n' "$TASKROOT" "$1"
}

task_meta_path(){
  printf '%s/SWE-%s/meta.json\n' "$TASKROOT" "$1"
}

validate_task_provenance(){
  local iid task meta
  for iid in "$@"; do
    task="$(task_problem_path "$iid")"
    meta="$(task_meta_path "$iid")"
    if [ ! -f "$task" ]; then
      echo "official SWE-Bench Pro task provenance required: missing PROBLEM.md for $iid at $task" >&2
      return 2
    fi
    if [ ! -f "$meta" ]; then
      echo "official SWE-Bench Pro task provenance required: missing meta.json for $iid at $meta" >&2
      return 2
    fi
    python3 - "$iid" "$DATASET_NAME" "$task" "$meta" <<'PY' || return 2
import json, sys

iid, dataset_name, problem_path, meta_path = sys.argv[1:]
expected_header = f"# SWE-bench-Pro: {iid}"
try:
    with open(problem_path, encoding="utf-8") as f:
        header = f.readline().strip()
    with open(meta_path, encoding="utf-8") as f:
        meta = json.load(f)
except Exception as exc:
    print(f"official SWE-Bench Pro task provenance required: unreadable task metadata for {iid}: {exc}", file=sys.stderr)
    raise SystemExit(1)
meta_iid = meta.get("instance_id")
meta_dataset = meta.get("dataset_name")
meta_label = meta.get("benchmark_label")
ok = (
    header == expected_header
    and meta_iid == iid
    and meta_dataset == dataset_name
    and meta_label == "SWE-bench-Pro"
)
if not ok:
    print(
        "official SWE-Bench Pro task provenance required: "
        f"iid={iid} header={header!r} meta_instance_id={meta_iid!r} "
        f"meta_dataset_name={meta_dataset!r} meta_benchmark_label={meta_label!r} "
        f"expected_header={expected_header!r} expected_dataset={dataset_name!r}",
        file=sys.stderr,
    )
raise SystemExit(0 if ok else 1)
PY
  done
}

find_pristine(){
  local iid="$1" root
  for root in "$SUITEROOT" /private/tmp/swe/suite /tmp/swe/suite; do
    if [ -d "$root/$iid/pristine/.git" ]; then
      printf '%s\n' "$root/$iid/pristine"
      return 0
    fi
  done
  return 1
}

task_base_commit(){
  python3 - "$(task_meta_path "$1")" <<'PY'
import json, sys
try:
    base = json.load(open(sys.argv[1])).get("base_commit") or ""
except Exception:
    base = ""
print(base if isinstance(base, str) else str(base))
PY
}

validate_suite_preflight(){
  local iid pristine expected actual searched
  for iid in "$@"; do
    pristine="$(find_pristine "$iid")" || {
      searched="$SUITEROOT/$iid/pristine,/private/tmp/swe/suite/$iid/pristine,/tmp/swe/suite/$iid/pristine"
      echo "official SWE-Bench Pro suite checkout required: missing .git for $iid expected=$SUITEROOT/$iid/pristine searched=$searched" >&2
      return 2
    }
    expected="$(task_base_commit "$iid")"
    if [ -z "$expected" ]; then
      echo "official SWE-Bench Pro task metadata requires base_commit for suite preflight: iid=$iid meta=$(task_meta_path "$iid")" >&2
      return 2
    fi
    actual="$(git -C "$pristine" rev-parse HEAD 2>/dev/null || true)"
    if [ -z "$actual" ]; then
      echo "official SWE-Bench Pro pristine checkout unreadable: iid=$iid pristine=$pristine" >&2
      return 2
    fi
    case "$actual" in
      "$expected"*) ;;
      *)
        echo "official SWE-Bench Pro pristine checkout base mismatch: iid=$iid pristine=$pristine expected_base=$expected actual_head=$actual" >&2
        return 2
        ;;
    esac
  done
}

act_schema_ok(){
  python3 - "$1" <<'PY'
import json, sys
fields = {"preconditions", "transformation", "effects", "cost", "receipt", "fidelity_battery"}
rows = []
try:
    with open(sys.argv[1]) as f:
        for line in f:
            if line.strip():
                rows.append(json.loads(line))
except Exception:
    print("false")
    raise SystemExit
ok = bool(rows) and all(isinstance(r.get("act"), dict) and fields <= set(r["act"]) for r in rows)
print("true" if ok else "false")
PY
}

validate_weights_bank(){
  local weights="$1"
  [ -f "$weights" ] || { echo "substrate weights file not found: $weights" >&2; return 2; }
  local canonical_path=false
  [ "$(realpath_file "$weights")" = "$(realpath_file "$HERE/.corpus/weights.jsonl")" ] && canonical_path=true
  local act_ok
  act_ok="$(act_schema_ok "$weights")"
  if [ "$canonical_path" = true ] && [ "$act_ok" = true ]; then
    echo "true"
    return 0
  fi
  if [ "${ATOMIC_ELEVATION_ALLOW_EXPERIMENTAL:-}" = "1" ]; then
    echo "false"
    return 0
  fi
  echo "noncanonical or non-ACT substrate bank rejected: $weights" >&2
  return 2
}

native_has_resolved_fields(){
  local baseline="$1"; shift
  python3 - "$baseline" "$@" <<'PY'
import json, sys
baseline = sys.argv[1]
tasks = sys.argv[2:]
try:
    data = json.load(open(baseline))
except Exception:
    print("false")
    raise SystemExit
instances = data.get("instances") or {}
def find(iid):
    if iid in instances:
        return instances[iid]
    short = iid.split("__", 1)[-1]
    return instances.get(short)
ok = bool(tasks) and all(isinstance(find(t), dict) and isinstance(find(t).get("resolved"), bool) for t in tasks)
print("true" if ok else "false")
PY
}

baseline_teacher_model(){
  python3 - "$1" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    print("unknown")
    raise SystemExit
print(data.get("model") or data.get("teacher_model") or "unknown")
PY
}

baseline_teacher_atomic(){
  python3 - "$1" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    print("false")
    raise SystemExit
atomic = data.get("atomic")
tooling = str(data.get("tooling") or data.get("protocol") or "").lower()
print("true" if atomic is True or "atomic" in tooling else "false")
PY
}

baseline_frontier_report(){
  local baseline="$1"; shift
  python3 - "$baseline" "$BENCHMARK_SUITE" "$DATASET_NAME" "$@" <<'PY'
import hashlib, json, re, sys
from pathlib import Path

baseline, benchmark_suite, dataset_name = sys.argv[1:4]
tasks = sys.argv[4:]

def emit(*values):
    print(" ".join("true" if v else "false" for v in values))

try:
    baseline_path = Path(baseline).resolve()
    data = json.loads(baseline_path.read_text(encoding="utf-8"))
except Exception:
    emit(False, False, False, False, False)
    raise SystemExit

role_ok = data.get("frontier_baseline") is True or data.get("baseline_role") == "frontier"
frozen_ok = data.get("frozen") is True or data.get("baseline_frozen") is True
official_ok = (
    data.get("official_docker") is True
    or data.get("official_harness") is True
    or data.get("scoring_harness") == "swebench.harness.run_evaluation"
)
dataset_ok = (
    data.get("benchmark_suite") == benchmark_suite
    and data.get("dataset_name") == dataset_name
    and data.get("benchmark_label") == "SWE-bench-Pro"
)
baseline_tasks = data.get("task_ids") or data.get("held_out_task_ids") or []
paired_ok = (
    isinstance(baseline_tasks, list)
    and bool(tasks)
    and len(baseline_tasks) == len(tasks)
    and set(baseline_tasks) == set(tasks)
)

instances = data.get("instances") or {}

def find_instance(iid):
    if iid in instances:
        return instances[iid]
    short = iid.split("__", 1)[-1]
    return instances.get(short)

def resolve_evidence_path(raw):
    if not isinstance(raw, str) or not raw:
        return None
    path = Path(raw)
    if not path.is_absolute():
        path = baseline_path.parent / path
    return path

def sha256_path(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def prediction_instance_ok(path, iid):
    try:
        with path.open(encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    return json.loads(line).get("instance_id") == iid
    except Exception:
        return False
    return False

def score_resolved_ok(path, resolved):
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return False
    matches = re.findall(r"Instances resolved:\s*(\d+)", text)
    if not matches:
        return False
    return int(matches[-1]) == (1 if resolved else 0)

receipt = data.get("frontier_receipt") or data.get("baseline_receipt") or {}
receipt_metadata_ok = (
    isinstance(receipt, dict)
    and receipt.get("format") == "swebench_pro_frontier_baseline_v1"
    and receipt.get("frozen") is True
    and receipt.get("official_docker") is True
    and receipt.get("scoring_harness") == "swebench.harness.run_evaluation"
    and receipt.get("benchmark_suite") == benchmark_suite
    and receipt.get("dataset_name") == dataset_name
    and receipt.get("benchmark_label") == "SWE-bench-Pro"
)
receipt_tasks = receipt.get("task_ids") if isinstance(receipt, dict) else []
receipt_paired_ok = isinstance(receipt_tasks, list) and receipt_tasks == tasks
evidence = receipt.get("evidence") if isinstance(receipt, dict) else None
receipt_ok = receipt_metadata_ok and receipt_paired_ok and isinstance(evidence, dict) and bool(tasks)

if receipt_ok:
    for iid in tasks:
        rec = evidence.get(iid)
        inst = find_instance(iid)
        if not isinstance(rec, dict) or not isinstance(inst, dict):
            receipt_ok = False
            break
        resolved = inst.get("resolved")
        if not isinstance(resolved, bool) or rec.get("resolved") != resolved:
            receipt_ok = False
            break
        pred = resolve_evidence_path(rec.get("prediction_jsonl"))
        score = resolve_evidence_path(rec.get("score_log"))
        if pred is None or score is None or not pred.is_file() or not score.is_file():
            receipt_ok = False
            break
        if rec.get("prediction_sha256") != sha256_path(pred):
            receipt_ok = False
            break
        if rec.get("score_log_sha256") != sha256_path(score):
            receipt_ok = False
            break
        if not prediction_instance_ok(pred, iid) or not score_resolved_ok(score, resolved):
            receipt_ok = False
            break

ok = role_ok and frozen_ok and official_ok and dataset_ok and paired_ok and receipt_ok
emit(ok, frozen_ok, official_ok, paired_ok, receipt_ok)
PY
}

tasks_anti_replay(){
  local baseline="$1"; shift
  python3 - "$baseline" "$@" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    print("false")
    raise SystemExit
tasks = set(sys.argv[2:])
teach = set(data.get("teach_task_ids") or data.get("teacher_task_ids") or [])
print("true" if tasks and (not teach or tasks.isdisjoint(teach)) else "false")
PY
}

native_resolved_count(){
  local baseline="$1"; shift
  python3 - "$baseline" "$@" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
instances = data.get("instances") or {}
def find(iid):
    if iid in instances:
        return instances[iid]
    short = iid.split("__", 1)[-1]
    return instances.get(short) or {}
print(sum(1 for t in sys.argv[2:] if find(t).get("resolved") is True))
PY
}

tasks_are_distinct(){
  python3 - "$@" <<'PY'
import sys
tasks = sys.argv[1:]
print("true" if tasks and len(tasks) == len(set(tasks)) else "false")
PY
}

tasks_hash(){
  python3 - "$@" <<'PY'
import hashlib, sys
payload = "\n".join(sys.argv[1:]).encode()
print(hashlib.sha256(payload).hexdigest())
PY
}

substrate_stats(){
  python3 - "$1" <<'PY'
import json, sys
rows = []
with open(sys.argv[1]) as f:
    for line in f:
        if line.strip():
            rows.append(json.loads(line))
proof_sum = sum(int(r.get("proof_n") or 1) for r in rows)
print(f"{len(rows)} {proof_sum}")
PY
}

prepare_weights_snapshot(){
  local source="$1" outdir="$2"
  local snapshot="$outdir/substrate_weights.jsonl"
  local meta="$outdir/substrate_weights.meta.json"
  local existing_samples
  existing_samples="$(find "$outdir" -maxdepth 1 -type f \( -name 'base_*.json' -o -name 'substrate_*.json' \) | wc -l | tr -d ' ')"
  if [ "$RESUME" = "1" ] && [ -s "$snapshot" ]; then
    if [ "$(act_schema_ok "$snapshot")" != "true" ]; then
      echo "elevation snapshot is not an ACT substrate bank: $snapshot" >&2
      return 2
    fi
    local snapshot_sha meta_sha
    snapshot_sha="$(sha256_file "$snapshot")"
    if [ -s "$meta" ]; then
      meta_sha="$(python3 - "$meta" <<'PY'
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("weights_sha256") or "")
except Exception:
    print("")
PY
)"
      if [ -n "$meta_sha" ] && [ "$meta_sha" != "$snapshot_sha" ]; then
        echo "elevation snapshot sha mismatch: meta=$meta_sha actual=$snapshot_sha" >&2
        return 2
      fi
    fi
    printf '%s\n' "$snapshot"
    return 0
  fi
  if [ "$RESUME" = "1" ] && [ "${existing_samples:-0}" != "0" ]; then
    echo "cannot resume elevation run without substrate_weights.jsonl snapshot: $outdir" >&2
    return 2
  fi
  cp "$source" "$snapshot" || return $?
  local snapshot_sha
  snapshot_sha="$(sha256_file "$snapshot")"
  python3 - "$meta" "$source" "$snapshot" "$snapshot_sha" "$canonical_act" <<'PY'
import json, os, sys
meta, source, snapshot, snapshot_sha, canonical_act = sys.argv[1:]
data = {
    "source_path": source,
    "source_realpath": os.path.realpath(source),
    "snapshot_path": snapshot,
    "weights_sha256": snapshot_sha,
    "canonical_act": canonical_act == "true",
}
open(meta, "w").write(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
  printf '%s\n' "$snapshot"
}

default_tasks=(psf__requests-1921 pytest-dev__pytest-5262 pytest-dev__pytest-7982 pylint-dev__pylint-7080 pallets__flask-5014)

if [ "${1:-}" = "--selftest" ]; then
  WEIGHTS="$(resolve_path "${2:-$HERE/.corpus/weights.jsonl}")"
  BASELINE="$(resolve_path "${3:-$HERE/native_baseline_suite.json}")"
  shift 3 || true
  TASKS=("$@")
  [ "${#TASKS[@]}" -gt 0 ] || TASKS=("${default_tasks[@]}")
  canonical_act="$(validate_weights_bank "$WEIGHTS")" || exit $?
  weights_sha="$(sha256_file "$WEIGHTS")"
  distinct="$(tasks_are_distinct "${TASKS[@]}")"
  native_fields="$(native_has_resolved_fields "$BASELINE" "${TASKS[@]}")"
  teacher_model="$(baseline_teacher_model "$BASELINE")"
  teacher_atomic="$(baseline_teacher_atomic "$BASELINE")"
  anti_replay="$(tasks_anti_replay "$BASELINE" "${TASKS[@]}")"
  held_out="$anti_replay"
  official_benchmark=false
  if is_official_benchmark; then official_benchmark=true; fi
  read -r frontier_baseline_provenance_ok frontier_baseline_frozen frontier_baseline_official_docker frontier_baseline_paired_tasks frontier_baseline_evidence_receipt_ok <<<"$(baseline_frontier_report "$BASELINE" "${TASKS[@]}")"
  read -r substrate_weight_count accumulation_index <<<"$(substrate_stats "$WEIGHTS")"
  echo "metric=elevation"
  echo "benchmark_suite=$BENCHMARK_SUITE"
  echo "benchmark_dataset_name=$DATASET_NAME"
  echo "official_benchmark=$official_benchmark"
  echo "task_root=$TASKROOT"
  echo "suite_root=$SUITEROOT"
  echo "task_provenance_enforced=true"
  echo "suite_preflight_enforced=true"
  echo "canonical_act=$canonical_act"
  echo "run_id=elevation_selftest_$(sanitize "${weights_sha:0:12}")_$(tasks_hash "${TASKS[@]}" | cut -c1-12)"
  echo "weights_sha256=$weights_sha"
  echo "student_model=$MODEL"
  echo "teacher_model=$teacher_model"
  echo "teacher_atomic=$teacher_atomic"
  echo "frontier_baseline_provenance_ok=$frontier_baseline_provenance_ok"
  echo "frontier_baseline_frozen=$frontier_baseline_frozen"
  echo "frontier_baseline_official_docker=$frontier_baseline_official_docker"
  echo "frontier_baseline_paired_tasks=$frontier_baseline_paired_tasks"
  echo "frontier_baseline_evidence_receipt_ok=$frontier_baseline_evidence_receipt_ok"
  echo "held_out=$held_out"
  echo "anti_replay=$anti_replay"
  echo "substrate_mode=accumulated_canonical_act"
  echo "control_arm=deepseek_v4_pro_without_substrate"
  echo "substrate_arm=deepseek_v4_pro_with_substrate"
  echo "resume_supported=true"
  echo "native_baseline_resolved_fields=$native_fields"
  echo "distinct_tasks=$distinct"
  echo "task_count=${#TASKS[@]}"
  echo "substrate_weight_count=$substrate_weight_count"
  echo "accumulation_index=$accumulation_index"
  echo "swebench_import_timeout_seconds=${ATOMIC_ELEVATION_IMPORT_TIMEOUT_SECONDS:-20}"
  if validate_swebench_python; then echo "swebench_importable=true"; else echo "swebench_importable=false"; fi
  echo "summary_fields=metric,run_id,benchmark_suite,benchmark_dataset_name,official_benchmark,task_provenance_ok,suite_preflight_ok,frontier_baseline_provenance_ok,frontier_baseline_evidence_receipt_ok,task_ids,distinct_tasks,native_resolved,frontier_baseline_resolved,atomic_base_resolved,deepseek_control_resolved,atomic_substrate_resolved,elevation_vs_atomic_base,elevation_vs_native,elevation_vs_frontier,elevation_vs_deepseek_control,accumulation_index,substrate_weight_count,weights_sha256,weights_sha256_initial,weights_sha256_final,weights_snapshot_path,canonical_act,student_model,teacher_model,teacher_atomic,held_out,anti_replay,sample_timeouts,score_failures,reused_samples,rerun_timeout_samples,elevation_valid"
  if [ "$canonical_act" = true ] && [ "$native_fields" = true ] && [ "$distinct" = true ] && [ "$teacher_atomic" = true ] && [ "$anti_replay" = true ] && [ "$official_benchmark" = true ] && [ "$frontier_baseline_provenance_ok" = true ] && [ "$frontier_baseline_evidence_receipt_ok" = true ]; then
    echo "elevation_valid_if_run=true"
  else
    echo "elevation_valid_if_run=false"
  fi
  exit 0
fi

RUN_TAG="${1:-ELEV001}"
BASELINE="$(resolve_path "${2:-$HERE/native_baseline_suite.json}")"
WEIGHTS="$(resolve_path "${3:-$HERE/.corpus/weights.jsonl}")"
shift 3 || true
TASKS=("$@")
[ "${#TASKS[@]}" -gt 0 ] || TASKS=("${default_tasks[@]}")

canonical_act="$(validate_weights_bank "$WEIGHTS")" || exit $?
weights_sha="$(sha256_file "$WEIGHTS")"
distinct="$(tasks_are_distinct "${TASKS[@]}")"
native_fields="$(native_has_resolved_fields "$BASELINE" "${TASKS[@]}")"
teacher_model="$(baseline_teacher_model "$BASELINE")"
teacher_atomic="$(baseline_teacher_atomic "$BASELINE")"
anti_replay="$(tasks_anti_replay "$BASELINE" "${TASKS[@]}")"
held_out="$anti_replay"
official_benchmark=false
if is_official_benchmark; then official_benchmark=true; fi
read -r frontier_baseline_provenance_ok frontier_baseline_frozen frontier_baseline_official_docker frontier_baseline_paired_tasks frontier_baseline_evidence_receipt_ok <<<"$(baseline_frontier_report "$BASELINE" "${TASKS[@]}")"
read -r substrate_weight_count accumulation_index <<<"$(substrate_stats "$WEIGHTS")"
SAMPLE_TIMEOUT_SECONDS="${ATOMIC_ELEVATION_SAMPLE_TIMEOUT_SECONDS:-900}"
SCORE_TIMEOUT_SECONDS="${ATOMIC_ELEVATION_SCORE_TIMEOUT_SECONDS:-1200}"
RESUME="${ATOMIC_ELEVATION_RESUME:-0}"
RERUN_TIMEOUTS="${ATOMIC_ELEVATION_RERUN_TIMEOUTS:-0}"

if [ "$distinct" != true ]; then
  echo "elevation stream requires distinct SWE-Bench task ids; duplicates are non-metric" >&2
  exit 2
fi
if [ "$official_benchmark" != true ]; then
  echo "official SWE-Bench Pro dataset required for Elevação: benchmark_suite=$BENCHMARK_SUITE dataset=$DATASET_NAME expected_dataset=ScaleAI/SWE-bench_Pro" >&2
  exit 2
fi
if [ "$frontier_baseline_provenance_ok" != true ]; then
  echo "paired official SWE-Bench Pro frontier baseline required: baseline=$BASELINE dataset=$DATASET_NAME frozen=$frontier_baseline_frozen official_docker=$frontier_baseline_official_docker paired_tasks=$frontier_baseline_paired_tasks evidence_receipt=$frontier_baseline_evidence_receipt_ok" >&2
  exit 2
fi
task_provenance_ok=false
if ! validate_task_provenance "${TASKS[@]}"; then
  exit 2
fi
task_provenance_ok=true
suite_preflight_ok=false
if ! validate_suite_preflight "${TASKS[@]}"; then
  exit 2
fi
suite_preflight_ok=true
if ! validate_swebench_python; then
  echo "swebench import failed for SWE_PYTHON=$SWE_PYTHON; refusing elevation run" >&2
  exit 2
fi
if ! validate_docker_api; then
  echo "docker API unavailable for official SWE-bench scoring; refusing elevation run" >&2
  exit 2
fi
source /tmp/.atomic_creds.sh 2>/dev/null || true
if [ -z "${DEEPSEEK_API_KEY:-}" ]; then
  echo "DEEPSEEK_API_KEY is required in env for elevation run" >&2
  exit 2
fi

task_hash="$(tasks_hash "${TASKS[@]}")"
OUTROOT="$HERE/evidence/ELEVATION"; mkdir -p "$OUTROOT"
RUN_ID="${ATOMIC_ELEVATION_RUN_ID:-elevation_$(sanitize "$RUN_TAG")_T${#TASKS[@]}_${weights_sha:0:12}_${task_hash:0:12}_$(date -u +%Y%m%dT%H%M%SZ)_$$}"
OUTDIR="$OUTROOT/$RUN_ID"; mkdir -p "$OUTDIR"
WEIGHTS_SOURCE="$WEIGHTS"
WEIGHTS_SNAPSHOT="$(prepare_weights_snapshot "$WEIGHTS_SOURCE" "$OUTDIR")" || exit $?
weights_sha_initial="$(sha256_file "$WEIGHTS_SNAPSHOT")"
weights_sha="$weights_sha_initial"
read -r substrate_weight_count accumulation_index <<<"$(substrate_stats "$WEIGHTS_SNAPSHOT")"
LOCKROOT="$OUTROOT/.locks"; mkdir -p "$LOCKROOT"
LOCKDIR="$LOCKROOT/$(sanitize "$RUN_TAG")_${weights_sha}_${task_hash}.lock"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  echo "elevation stream already active for tag=$RUN_TAG tasks_sha256=$task_hash weights_sha256=$weights_sha" >&2
  exit 75
fi
trap 'rm -rf "$LOCKDIR"' EXIT

export DEEPSEEK_MODEL="$MODEL" DEEPSEEK_TIMEOUT="${DEEPSEEK_TIMEOUT:-120}" DEEPSEEK_TOTAL_TIMEOUT="${DEEPSEEK_TOTAL_TIMEOUT:-180}"

find_pristine(){
  local iid="$1"
  for root in "$SUITEROOT" /private/tmp/swe/suite /tmp/swe/suite; do
    if [ -d "$root/$iid/pristine/.git" ]; then
      printf '%s\n' "$root/$iid/pristine"
      return 0
    fi
  done
  return 1
}

score_prediction(){
  local pred="$1" run_id="$2" log="$3"
  python3 - "$SCORE_TIMEOUT_SECONDS" "$SWE_PYTHON" "$DATASET_NAME" "$pred" "$run_id" "$log" <<'PY' >/dev/null 2>&1
import subprocess, sys
timeout, swe_python, dataset_name, pred, run_id, log_path = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]
cmd = [
    swe_python, "-m", "swebench.harness.run_evaluation",
    "--dataset_name", dataset_name,
    "--predictions_path", pred,
    "--run_id", run_id,
    "--max_workers", "1",
    "--cache_level", "instance",
]
with open(log_path, "w") as log:
    try:
        completed = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
    except subprocess.TimeoutExpired:
        log.write(f"\nSWE_SCORE_TIMEOUT seconds={timeout}\n")
        raise SystemExit(124)
raise SystemExit(completed.returncode)
PY
}

sample_error(){
  python3 - "$1" <<'PY'
import json, sys
try:
    print((json.load(open(sys.argv[1])).get("error") or ""))
except Exception:
    print("")
PY
}

score_resolved(){
  grep -aE "Instances resolved:" "$1" | tail -1 | grep -oE "[0-9]+$" || true
}

run_one(){
  local arm="$1" iid="$2" idx="$3"
  local pristine
  pristine="$(find_pristine "$iid")" || {
    echo "$arm $iid: resolved=? timeout=0 score_bad=1 setup_failed=1"
    return
  }
  local task
  task="$(task_problem_path "$iid")"
  local wd="/private/tmp/swe/round/ELEVATION/${RUN_ID}_${arm}_${idx}_$(sanitize "$iid")"
  local out="$OUTDIR/${arm}_${idx}_$(sanitize "$iid").json"
  local pred="$OUTDIR/pred_${arm}_${idx}_$(sanitize "$iid").jsonl"
  local score_log="$OUTDIR/score_${arm}_${idx}_$(sanitize "$iid").log"
  local rerun_timeout=0
  if [ "$RESUME" = "1" ] && [ -s "$out" ] && [ -s "$pred" ] && [ -s "$score_log" ] && grep -qaE "Instances resolved:" "$score_log"; then
    local prior_error prior_res
    prior_error="$(sample_error "$out")"
    if [ "$prior_error" = "agent_timeout" ] && [ "$RERUN_TIMEOUTS" = "1" ]; then
      rm -f "$out" "$pred" "$score_log"
      rerun_timeout=1
    else
      prior_res="$(score_resolved "$score_log")"
      local prior_timeout=0
      [ "$prior_error" = "agent_timeout" ] && prior_timeout=1
      echo "$arm $iid: resolved=${prior_res:-?} timeout=$prior_timeout score_timeout=0 score_bad=0 reused=1 rerun_timeout=0"
      return
    fi
  fi
  if [ ! -f "$task" ] || ! rm -rf "$wd" || ! mkdir -p "$(dirname "$wd")" || ! cp -R "$pristine" "$wd"; then
    python3 - "$out" <<'PY'
import json, sys
json.dump({"final_diff": "", "edits_applied": 0, "error": "scratch_setup_failed"}, open(sys.argv[1], "w"))
PY
    echo "$arm $iid: resolved=? timeout=0 score_timeout=0 score_bad=1 setup_failed=1 reused=0 rerun_timeout=$rerun_timeout"
    return
  fi
  git -C "$wd" reset --hard -q HEAD; git -C "$wd" clean -fdq
  if [ "$arm" = "substrate" ]; then
    export ATOMIC_WEIGHTS_FILE="$WEIGHTS_SNAPSHOT"
  else
    unset ATOMIC_WEIGHTS_FILE
  fi
  local timeout_hit=0
  python3 - "$SAMPLE_TIMEOUT_SECONDS" "$DRIVER" "$wd" "$task" "$out" <<'PY' >/dev/null 2>&1
import json, subprocess, sys
timeout = int(sys.argv[1])
driver, wd, task, out = sys.argv[2:]
cmd = [sys.executable, driver, "--workdir", wd, "--task", task, "--gate", "NONE", "--out", out, "--max-steps", "60"]
try:
    completed = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=timeout)
except subprocess.TimeoutExpired:
    json.dump({"final_diff": "", "edits_applied": 0, "error": "agent_timeout", "timeout_seconds": timeout}, open(out, "w"))
    raise SystemExit(124)
if completed.returncode != 0 and not __import__("os").path.exists(out):
    json.dump({"final_diff": "", "edits_applied": 0, "error": "agent_exit", "exit_code": completed.returncode}, open(out, "w"))
raise SystemExit(completed.returncode)
PY
  [ "$?" -eq 124 ] && timeout_hit=1
  [ -s "$out" ] || python3 - "$out" <<'PY'
import json, sys
json.dump({"final_diff": "", "edits_applied": 0, "error": "missing_agent_output"}, open(sys.argv[1], "w"))
PY
  python3 - "$out" "$pred" "$iid" "$arm" <<'PY'
import json, sys
out, pred, iid, arm = sys.argv[1:]
d = json.load(open(out))
open(pred, "w").write(json.dumps({"instance_id": iid, "model_name_or_path": f"elevation-{arm}", "model_patch": d.get("final_diff") or ""}) + "\n")
PY
  local score_bad=0 score_timeout=0
  score_prediction "$pred" "${RUN_ID}_${arm}_${idx}_$(sanitize "$iid")" "$score_log"
  local score_status=$?
  [ "$score_status" -eq 124 ] && score_timeout=1
  local res
  res="$(grep -aE "Instances resolved:" "$score_log" | tail -1 | grep -oE "[0-9]+$" || true)"
  [ -z "${res:-}" ] && score_bad=1
  rm -rf "$wd"
  echo "$arm $iid: resolved=${res:-?} timeout=$timeout_hit score_timeout=$score_timeout score_bad=$score_bad reused=0 rerun_timeout=$rerun_timeout"
}

echo "=== ELEVATION STREAM $RUN_ID ==="
echo "tasks=${TASKS[*]}"
echo "weights_sha256_initial=$weights_sha_initial canonical_act=$canonical_act accumulation_index=$accumulation_index"
echo "weights_snapshot_path=$WEIGHTS_SNAPSHOT"
echo "frontier_baseline_resolved_fields=$native_fields teacher_model=$teacher_model teacher_atomic=$teacher_atomic held_out=$held_out anti_replay=$anti_replay baseline=$BASELINE"
echo "frontier_baseline_provenance_ok=$frontier_baseline_provenance_ok frozen=$frontier_baseline_frozen official_docker=$frontier_baseline_official_docker paired_tasks=$frontier_baseline_paired_tasks evidence_receipt=$frontier_baseline_evidence_receipt_ok"
echo "task_root=$TASKROOT suite_root=$SUITEROOT task_provenance_ok=$task_provenance_ok suite_preflight_ok=$suite_preflight_ok"

atomic_base_resolved=0; atomic_substrate_resolved=0; sample_timeouts=0; score_failures=0; reused_samples=0; rerun_timeout_samples=0
idx=0
for iid in "${TASKS[@]}"; do
  idx=$((idx+1))
  r="$(run_one base "$iid" "$idx")"; echo "$r"
  grep -q "resolved=1" <<<"$r" && atomic_base_resolved=$((atomic_base_resolved+1))
  grep -q " timeout=1 " <<<"$r" && sample_timeouts=$((sample_timeouts+1))
  grep -q "score_bad=1" <<<"$r" && score_failures=$((score_failures+1))
  grep -q "reused=1" <<<"$r" && reused_samples=$((reused_samples+1))
  grep -q "rerun_timeout=1" <<<"$r" && rerun_timeout_samples=$((rerun_timeout_samples+1))
done
idx=0
for iid in "${TASKS[@]}"; do
  idx=$((idx+1))
  r="$(run_one substrate "$iid" "$idx")"; echo "$r"
  grep -q "resolved=1" <<<"$r" && atomic_substrate_resolved=$((atomic_substrate_resolved+1))
  grep -q " timeout=1 " <<<"$r" && sample_timeouts=$((sample_timeouts+1))
  grep -q "score_bad=1" <<<"$r" && score_failures=$((score_failures+1))
  grep -q "reused=1" <<<"$r" && reused_samples=$((reused_samples+1))
  grep -q "rerun_timeout=1" <<<"$r" && rerun_timeout_samples=$((rerun_timeout_samples+1))
done

native_resolved_value="null"
if [ "$native_fields" = true ]; then
  native_resolved_value="$(native_resolved_count "$BASELINE" "${TASKS[@]}")"
fi
weights_sha_final="$(sha256_file "$WEIGHTS_SNAPSHOT")"

python3 - "$OUTDIR/elevation_summary.json" "$RUN_ID" "$BENCHMARK_SUITE" "$DATASET_NAME" "$official_benchmark" "$task_provenance_ok" "$suite_preflight_ok" "$frontier_baseline_provenance_ok" "$frontier_baseline_evidence_receipt_ok" "$weights_sha_initial" "$weights_sha_final" "$canonical_act" "$MODEL" \
  "$teacher_model" "$teacher_atomic" "$held_out" "$anti_replay" \
  "$native_fields" "$native_resolved_value" "$atomic_base_resolved" "$atomic_substrate_resolved" \
  "$accumulation_index" "$substrate_weight_count" "$sample_timeouts" "$score_failures" \
  "$reused_samples" "$rerun_timeout_samples" "$WEIGHTS_SNAPSHOT" "${TASKS[@]}" <<'PY'
import json, sys
out, run_id, benchmark_suite, benchmark_dataset_name, official_benchmark, task_provenance_ok, suite_preflight_ok, frontier_baseline_provenance_ok, frontier_baseline_evidence_receipt_ok, weights_sha_initial, weights_sha_final, canonical_act, model = sys.argv[1:14]
teacher_model, teacher_atomic, held_out, anti_replay = sys.argv[14:18]
native_fields, native_resolved_raw, atomic_base, atomic_substrate = sys.argv[18:22]
accumulation_index, substrate_weight_count, sample_timeouts, score_failures = map(int, sys.argv[22:26])
reused_samples, rerun_timeout_samples = map(int, sys.argv[26:28])
weights_snapshot_path = sys.argv[28]
tasks = sys.argv[29:]
atomic_base = int(atomic_base); atomic_substrate = int(atomic_substrate)
native_resolved = None if native_resolved_raw == "null" else int(native_resolved_raw)
data = {
    "metric": "elevation",
    "run_id": run_id,
    "benchmark_suite": benchmark_suite,
    "benchmark_dataset_name": benchmark_dataset_name,
    "official_benchmark": official_benchmark == "true",
    "task_provenance_ok": task_provenance_ok == "true",
    "suite_preflight_ok": suite_preflight_ok == "true",
    "frontier_baseline_provenance_ok": frontier_baseline_provenance_ok == "true",
    "frontier_baseline_evidence_receipt_ok": frontier_baseline_evidence_receipt_ok == "true",
    "task_ids": tasks,
    "distinct_tasks": len(tasks) == len(set(tasks)) and bool(tasks),
    "native_resolved": native_resolved,
    "frontier_baseline_resolved": native_resolved,
    "atomic_base_resolved": atomic_base,
    "deepseek_control_resolved": atomic_base,
    "atomic_substrate_resolved": atomic_substrate,
    "elevation_vs_atomic_base": atomic_substrate - atomic_base,
    "elevation_vs_native": None if native_resolved is None else atomic_substrate - native_resolved,
    "elevation_vs_frontier": None if native_resolved is None else atomic_substrate - native_resolved,
    "elevation_vs_deepseek_control": atomic_substrate - atomic_base,
    "accumulation_index": accumulation_index,
    "substrate_weight_count": substrate_weight_count,
    "weights_sha256": weights_sha_initial,
    "weights_sha256_initial": weights_sha_initial,
    "weights_sha256_final": weights_sha_final,
    "weights_snapshot_path": weights_snapshot_path,
    "canonical_act": canonical_act == "true",
    "student_model": model,
    "teacher_model": teacher_model,
    "teacher_atomic": teacher_atomic == "true",
    "held_out": held_out == "true",
    "anti_replay": anti_replay == "true",
    "sample_timeouts": sample_timeouts,
    "score_failures": score_failures,
    "reused_samples": reused_samples,
    "rerun_timeout_samples": rerun_timeout_samples,
    "elevation_valid": (
        canonical_act == "true"
        and official_benchmark == "true"
        and task_provenance_ok == "true"
        and suite_preflight_ok == "true"
        and frontier_baseline_provenance_ok == "true"
        and frontier_baseline_evidence_receipt_ok == "true"
        and native_fields == "true"
        and teacher_atomic == "true"
        and anti_replay == "true"
        and len(tasks) == len(set(tasks))
        and bool(tasks)
        and sample_timeouts == 0
        and score_failures == 0
    ),
}
open(out, "w").write(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
echo "Elevation summary: $OUTDIR/elevation_summary.json"
