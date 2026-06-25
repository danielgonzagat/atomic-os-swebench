#!/usr/bin/env bash
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWE_PYTHON="${ATOMIC_FRONTIER_SWE_PYTHON:-/opt/homebrew/bin/python3}"
BENCHMARK_SUITE="${ATOMIC_FRONTIER_BENCHMARK_SUITE:-swe_bench_pro}"
DATASET_NAME="${ATOMIC_FRONTIER_DATASET_NAME:-ScaleAI/SWE-bench_Pro}"
TASKROOT="${ATOMIC_FRONTIER_TASK_ROOT:-$HERE/tasks}"
SUITEROOT="${ATOMIC_FRONTIER_SUITE_ROOT:-${ATOMIC_SWE_SUITE_ROOT:-/tmp/swe/suite}}"
FREEZER="${ATOMIC_FRONTIER_FREEZER:-$HERE/freeze_frontier_baseline.py}"
STREAM="${ATOMIC_FRONTIER_STREAM:-$HERE/run_elevation_stream.sh}"
WEIGHTS="${ATOMIC_FRONTIER_WEIGHTS:-$HERE/.corpus/weights.jsonl}"
FRONTIER_MODEL="${ATOMIC_FRONTIER_MODEL:-frontier-teacher}"
SAMPLE_TIMEOUT_SECONDS="${ATOMIC_FRONTIER_SAMPLE_TIMEOUT_SECONDS:-3600}"
SCORE_TIMEOUT_SECONDS="${ATOMIC_FRONTIER_SCORE_TIMEOUT_SECONDS:-1200}"
OUTROOT="${ATOMIC_FRONTIER_OUTROOT:-$HERE/evidence/FRONTIER_BASELINE}"
DEFAULT_FRONTIER_AGENT_CMD="$HERE/frontier_atomic_agent_cmd.sh"
FRONTIER_AGENT_CMD="${ATOMIC_FRONTIER_AGENT_CMD:-$DEFAULT_FRONTIER_AGENT_CMD}"

usage() {
  cat >&2 <<'USAGE'
Usage:
  run_frontier_baseline.sh --selftest [TASK_ID ...]
  run_frontier_baseline.sh RUN_TAG OUT_BASELINE_JSON TASK_ID [TASK_ID ...]

Runtime uses ATOMIC_FRONTIER_AGENT_CMD when provided; otherwise it uses the
canonical frontier_atomic_agent_cmd.sh adapter. The command is executed once per
task with ATOMIC_FRONTIER_WORKDIR, ATOMIC_FRONTIER_TASK, ATOMIC_FRONTIER_OUT,
ATOMIC_FRONTIER_INSTANCE_ID, and ATOMIC_FRONTIER_MODEL in the environment. It
must write JSON to ATOMIC_FRONTIER_OUT containing a string field named final_diff.
USAGE
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

sanitize() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

is_official_benchmark() {
  [[ "$BENCHMARK_SUITE" == "swe_bench_pro" && "$DATASET_NAME" == "ScaleAI/SWE-bench_Pro" ]]
}

resolve_task_dir() {
  local task_id="$1"
  local direct="$TASKROOT/$task_id"
  local prefixed="$TASKROOT/SWE-$task_id"
  if [[ -d "$direct" ]]; then
    printf '%s\n' "$direct"
    return 0
  fi
  if [[ -d "$prefixed" ]]; then
    printf '%s\n' "$prefixed"
    return 0
  fi
  return 1
}

task_problem_path() {
  local dir
  if dir="$(resolve_task_dir "$1")"; then
    if [[ -f "$dir/problem.json" ]]; then
      printf '%s/problem.json\n' "$dir"
      return 0
    fi
    printf '%s/PROBLEM.md\n' "$dir"
    return 0
  fi
  printf '%s/SWE-%s/PROBLEM.md\n' "$TASKROOT" "$1"
}

task_meta_path() {
  local dir
  if dir="$(resolve_task_dir "$1")"; then
    printf '%s/meta.json\n' "$dir"
    return 0
  fi
  printf '%s/SWE-%s/meta.json\n' "$TASKROOT" "$1"
}

tasks_hash() {
  "$SWE_PYTHON" - "$@" <<'PYHASH'
import hashlib
import sys
payload = "\n".join(sys.argv[1:]).encode()
print(hashlib.sha256(payload).hexdigest())
PYHASH
}

tasks_are_distinct() {
  "$SWE_PYTHON" - "$@" <<'PYDISTINCT'
import sys
seen = set()
for task in sys.argv[1:]:
    if task in seen:
        print(f"duplicate task id: {task}", file=sys.stderr)
        sys.exit(1)
    seen.add(task)
PYDISTINCT
}

validate_swebench_python() {
  "$SWE_PYTHON" - <<'PYSWEBENCH'
import importlib.util
import sys
if importlib.util.find_spec("swebench.harness.run_evaluation") is None:
    print("swebench.harness.run_evaluation import is required", file=sys.stderr)
    sys.exit(1)
PYSWEBENCH
}

validate_docker_api() {
  "$SWE_PYTHON" - <<'PYDOCKER'
import docker
client = docker.from_env()
client.ping()
PYDOCKER
}

validate_task_provenance() {
  local task_id="$1"
  local problem meta
  problem="$(task_problem_path "$task_id")"
  meta="$(task_meta_path "$task_id")"
  if [[ ! -f "$problem" || ! -f "$meta" ]]; then
    echo "official Pro task metadata is required for $task_id" >&2
    return 1
  fi
  "$SWE_PYTHON" - "$task_id" "$problem" "$meta" "$DATASET_NAME" <<'PYPROVENANCE'
import json
import sys

task_id, problem_path, meta_path, dataset_name = sys.argv[1:5]
meta = json.load(open(meta_path, encoding="utf-8"))
if problem_path.endswith(".json"):
    problem_payload = json.load(open(problem_path, encoding="utf-8"))
    problem_id = problem_payload.get("instance_id")
    if problem_id != task_id:
        print(f"problem.json instance_id mismatch for {task_id}: {problem_id!r}", file=sys.stderr)
        sys.exit(1)
else:
    header = open(problem_path, encoding="utf-8").readline().strip()
    expected_header = f"# SWE-bench-Pro: {task_id}"
    if header != expected_header:
        print(f"PROBLEM.md header mismatch for {task_id}: {header!r} != {expected_header!r}", file=sys.stderr)
        sys.exit(1)
if meta.get("instance_id") != task_id:
    print(f"meta.json instance_id mismatch for {task_id}", file=sys.stderr)
    sys.exit(1)
if meta.get("dataset_name") != dataset_name:
    print(f"dataset mismatch for {task_id}: {meta.get('dataset_name')} != {dataset_name}", file=sys.stderr)
    sys.exit(1)
if meta.get("benchmark_label") not in (None, "SWE-bench-Pro"):
    print(f"benchmark label mismatch for {task_id}: {meta.get('benchmark_label')}", file=sys.stderr)
    sys.exit(1)
if meta.get("benchmark_suite") not in (None, "swe_bench_pro"):
    print(f"benchmark suite mismatch for {task_id}: {meta.get('benchmark_suite')}", file=sys.stderr)
    sys.exit(1)
if not meta.get("base_commit"):
    print(f"base_commit missing for {task_id}", file=sys.stderr)
    sys.exit(1)
PYPROVENANCE
}

find_pristine() {
  local task_id="$1"
  local task_dir root candidate
  for root in "$SUITEROOT" /private/tmp/swe/suite /tmp/swe/suite; do
    candidate="$root/$task_id/pristine"
    if [[ -d "$candidate/.git" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  if task_dir="$(resolve_task_dir "$task_id")"; then
    for candidate in "$task_dir/pristine" "$task_dir/repo" "$task_dir/worktree"; do
      if [[ -d "$candidate/.git" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
  fi
  echo "no pristine git checkout found for $task_id" >&2
  return 1
}

task_base_commit() {
  "$SWE_PYTHON" - "$(task_meta_path "$1")" <<'PYBASE'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["base_commit"])
PYBASE
}

validate_suite_preflight() {
  local task_id="$1"
  local pristine="$2"
  local base_commit="$3"
  git -C "$pristine" cat-file -e "$base_commit^{commit}" >/dev/null 2>&1 || {
    echo "base commit $base_commit missing in pristine checkout for $task_id" >&2
    return 1
  }
  local head
  head="$(git -C "$pristine" rev-parse HEAD)" || return 1
  if [[ "$head" != "$base_commit" ]]; then
    echo "pristine checkout for $task_id is not at base commit ($head != $base_commit)" >&2
    return 1
  fi
}

run_frontier_agent() {
  local task_id="$1"
  local workdir="$2"
  local out_json="$3"
  ATOMIC_FRONTIER_WORKDIR="$workdir" \
  ATOMIC_FRONTIER_TASK="$task_id" \
  ATOMIC_FRONTIER_INSTANCE_ID="$task_id" \
  ATOMIC_FRONTIER_OUT="$out_json" \
  ATOMIC_FRONTIER_MODEL="$FRONTIER_MODEL" \
  ATOMIC_FRONTIER_AGENT_CMD="$FRONTIER_AGENT_CMD" \
  "$SWE_PYTHON" - "$SAMPLE_TIMEOUT_SECONDS" <<'PYAGENT'
import os
import subprocess
import sys

timeout = int(sys.argv[1])
cmd = os.environ["ATOMIC_FRONTIER_AGENT_CMD"]
try:
    result = subprocess.run(cmd, shell=True, timeout=timeout, env=os.environ.copy())
except subprocess.TimeoutExpired:
    print(f"frontier agent timed out after {timeout}s", file=sys.stderr)
    sys.exit(124)
sys.exit(result.returncode)
PYAGENT
}

extract_final_diff() {
  local agent_json="$1"
  local prediction_jsonl="$2"
  local task_id="$3"
  "$SWE_PYTHON" - "$agent_json" "$prediction_jsonl" "$task_id" "$FRONTIER_MODEL" <<'PYPREDICT'
import json
import sys

agent_path, prediction_path, task_id, model = sys.argv[1:5]
try:
    payload = json.load(open(agent_path, encoding="utf-8"))
except Exception as exc:
    print(f"agent output is not valid JSON: {exc}", file=sys.stderr)
    sys.exit(1)
patch = payload.get("final_diff")
if not isinstance(patch, str):
    print("agent output must contain string field final_diff", file=sys.stderr)
    sys.exit(1)
record = {
    "instance_id": task_id,
    "model_name_or_path": model,
    "model_patch": patch,
}
with open(prediction_path, "w", encoding="utf-8") as handle:
    handle.write(json.dumps(record, sort_keys=True) + "\n")
PYPREDICT
}

score_prediction() {
  local task_id="$1"
  local prediction_jsonl="$2"
  local run_id="$3"
  local score_log="$4"
  local score_root="$OUTROOT/$run_id/score-$task_id"
  mkdir -p "$score_root"
  "$SWE_PYTHON" - "$SCORE_TIMEOUT_SECONDS" "$DATASET_NAME" "$prediction_jsonl" "$score_root" "$task_id" "$score_log" <<'PYSCORE'
import os
import subprocess
import sys

timeout, dataset_name, prediction_jsonl, score_root, task_id, score_log = sys.argv[1:7]
cmd = [
    sys.executable,
    "-m",
    "swebench.harness.run_evaluation",
    "--dataset_name",
    dataset_name,
    "--predictions_path",
    prediction_jsonl,
    "--run_id",
    f"frontier-{task_id}",
    "--max_workers",
    "1",
    "--namespace",
    "none",
    "--report_dir",
    score_root,
    "--instance_ids",
    task_id,
]
env = os.environ.copy()
env.setdefault("SWE_BENCH_DOCKER_WORKDIR", score_root)
with open(score_log, "w", encoding="utf-8") as log:
    try:
        result = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, timeout=int(timeout), env=env)
    except subprocess.TimeoutExpired:
        log.write(f"\nSCORE_TIMEOUT after {timeout}s\n")
        sys.exit(124)
sys.exit(result.returncode)
PYSCORE
}

score_resolved() {
  "$SWE_PYTHON" - "$1" <<'PYRESOLVED'
import re
import sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
matches = re.findall(r"Instances resolved:\s*(\d+)", text)
if not matches:
    print("score log missing Instances resolved verdict", file=sys.stderr)
    sys.exit(2)
value = int(matches[-1])
if value not in (0, 1):
    print(f"score log resolved count must be 0 or 1, got {value}", file=sys.stderr)
    sys.exit(2)
print("true" if value == 1 else "false")
PYRESOLVED
}

baseline_receipt_ok() {
  local baseline="$1"
  shift
  [[ -x "$STREAM" ]] || return 1
  "$STREAM" --selftest "$WEIGHTS" "$baseline" "$@" 2>/dev/null | grep -q '^frontier_baseline_evidence_receipt_ok=true$'
}

task_layout_ok() {
  local task_id problem meta ok=true
  for task_id in "$@"; do
    problem="$(task_problem_path "$task_id")"
    meta="$(task_meta_path "$task_id")"
    if [[ ! -f "$problem" || ! -f "$meta" ]]; then
      ok=false
    fi
  done
  printf '%s\n' "$ok"
}

task_provenance_ok() {
  local task_id ok=true
  for task_id in "$@"; do
    if ! validate_task_provenance "$task_id" >/dev/null 2>&1; then
      ok=false
    fi
  done
  printf '%s\n' "$ok"
}

task_provenance_sha256() {
  local task_id problem meta
  local args=()
  for task_id in "$@"; do
    if ! validate_task_provenance "$task_id" >/dev/null 2>&1; then
      printf '\n'
      return 0
    fi
    problem="$(task_problem_path "$task_id")"
    meta="$(task_meta_path "$task_id")"
    args+=("$task_id" "$problem" "$meta")
  done
  "$SWE_PYTHON" - "$DATASET_NAME" "${args[@]}" <<'PYPROVENANCESHA'
import hashlib
import json
import os
import sys

dataset_name, *items = sys.argv[1:]
if len(items) % 3:
    print("", end="")
    raise SystemExit(0)

digest = hashlib.sha256()
digest.update(f"dataset_name={dataset_name}\n".encode())
for offset in range(0, len(items), 3):
    task_id, problem_path, meta_path = items[offset : offset + 3]
    with open(problem_path, "rb") as handle:
        problem_bytes = handle.read()
    with open(meta_path, "rb") as handle:
        meta_bytes = handle.read()
    meta_payload = json.loads(meta_bytes.decode("utf-8"))
    digest.update(f"task_id={task_id}\n".encode())
    digest.update(f"problem_file={os.path.basename(problem_path)}\n".encode())
    digest.update(f"problem_sha256={hashlib.sha256(problem_bytes).hexdigest()}\n".encode())
    digest.update(f"meta_sha256={hashlib.sha256(meta_bytes).hexdigest()}\n".encode())
    for key in ("instance_id", "dataset_name", "benchmark_label", "benchmark_suite", "base_commit"):
        value = meta_payload.get(key)
        digest.update(f"meta.{key}={json.dumps(value, sort_keys=True)}\n".encode())
print(digest.hexdigest())
PYPROVENANCESHA
}

suite_pristine_layout_ok() {
  local task_id ok=true
  for task_id in "$@"; do
    if ! find_pristine "$task_id" >/dev/null 2>&1; then
      ok=false
    fi
  done
  printf '%s\n' "$ok"
}

emit_selftest() {
  local official="false"
  local task_layout task_provenance task_provenance_sha suite_pristine_layout
  if is_official_benchmark; then
    official="true"
  fi
  task_layout="$(task_layout_ok "$@")"
  task_provenance="$(task_provenance_ok "$@")"
  task_provenance_sha="$(task_provenance_sha256 "$@")"
  suite_pristine_layout="$(suite_pristine_layout_ok "$@")"
  cat <<EOF
metric=frontier_baseline_receipt
metric_claim=false
benchmark_suite=$BENCHMARK_SUITE
benchmark_dataset_name=$DATASET_NAME
official_benchmark=$official
requires_frontier_agent_cmd=false
default_frontier_agent_cmd=$DEFAULT_FRONTIER_AGENT_CMD
requires_model_credentials=true
credential_source=env
credential_file_allowed=false
requires_official_scorer=true
freezer_path=$FREEZER
task_provenance_enforced=true
suite_preflight_enforced=true
task_layout_ok=$task_layout
task_provenance_ok=$task_provenance
task_provenance_sha256=$task_provenance_sha
suite_pristine_layout_ok=$suite_pristine_layout
score_timeout_seconds=$SCORE_TIMEOUT_SECONDS
sample_timeout_seconds=$SAMPLE_TIMEOUT_SECONDS
summary_fields=metric,metric_claim,benchmark_suite,benchmark_dataset_name,official_benchmark,task_provenance_ok,task_provenance_sha256,suite_preflight_ok,frontier_baseline_path,frontier_baseline_evidence_receipt_ok,sample_failures,score_failures
EOF
}

write_summary() {
  "$SWE_PYTHON" - "$@" <<'PYSUMMARY'
import json
import sys
(
    out_path,
    baseline_path,
    receipt_ok,
    task_provenance_ok,
    task_provenance_sha256,
    suite_preflight_ok,
    sample_failures,
    score_failures,
    task_hash,
    dataset_name,
    benchmark_suite,
    frontier_model,
    *tasks,
) = sys.argv[1:]
payload = {
    "metric": "frontier_baseline_receipt",
    "metric_claim": False,
    "benchmark_suite": benchmark_suite,
    "benchmark_dataset_name": dataset_name,
    "official_benchmark": benchmark_suite == "swe_bench_pro" and dataset_name == "ScaleAI/SWE-bench_Pro",
    "frontier_model": frontier_model,
    "task_ids": tasks,
    "task_ids_sha256": task_hash,
    "task_provenance_ok": task_provenance_ok == "true",
    "task_provenance_sha256": task_provenance_sha256,
    "suite_preflight_ok": suite_preflight_ok == "true",
    "frontier_baseline_path": baseline_path,
    "frontier_baseline_evidence_receipt_ok": receipt_ok == "true",
    "sample_failures": int(sample_failures),
    "score_failures": int(score_failures),
}
with open(out_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYSUMMARY
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--selftest" ]]; then
  shift
  emit_selftest "$@"
  exit 0
fi

if [[ $# -lt 3 ]]; then
  usage
  exit 2
fi

RUN_TAG="$1"
OUT_BASELINE="$2"
shift 2
TASKS=("$@")

if ! is_official_benchmark; then
  echo "official SWE-Bench Pro dataset required for frontier baseline receipt" >&2
  exit 2
fi

if [[ -z "${ATOMIC_FRONTIER_AGENT_CMD:-}" ]]; then
  if [[ ! -x "$DEFAULT_FRONTIER_AGENT_CMD" ]]; then
    echo "default frontier agent command is required: $DEFAULT_FRONTIER_AGENT_CMD" >&2
    exit 2
  fi
  if [[ -z "${DEEPSEEK_API_KEY:-}" ]]; then
    echo "DEEPSEEK_API_KEY is required for default frontier atomic agent command" >&2
    exit 2
  fi
fi

if ! tasks_are_distinct "${TASKS[@]}"; then
  exit 2
fi

if [[ ! -f "$FREEZER" ]]; then
  echo "freeze_frontier_baseline.py is required at $FREEZER" >&2
  exit 2
fi

validate_swebench_python || exit 2
validate_docker_api || exit 2

RUN_ID="$(sanitize "$RUN_TAG")-$(date -u +%Y%m%dT%H%M%SZ)"
OUTDIR="$OUTROOT/$RUN_ID"
mkdir -p "$OUTDIR" "$(dirname "$OUT_BASELINE")"

sample_failures=0
score_failures=0
task_provenance_ok=true
suite_preflight_ok=true
freeze_args=("--out" "$OUT_BASELINE" "--model" "$FRONTIER_MODEL" "--teach-task-id" "$RUN_TAG")

for task_id in "${TASKS[@]}"; do
  validate_task_provenance "$task_id" || exit 2
  pristine="$(find_pristine "$task_id")" || exit 2
  base_commit="$(task_base_commit "$task_id")" || exit 2
  validate_suite_preflight "$task_id" "$pristine" "$base_commit" || exit 2

  workdir="$OUTDIR/workdir-$task_id"
  agent_json="$OUTDIR/agent-$task_id.json"
  prediction_jsonl="$OUTDIR/prediction-$task_id.jsonl"
  score_log="$OUTDIR/score-$task_id.log"
  rm -rf "$workdir"
  cp -R "$pristine" "$workdir"

  if ! run_frontier_agent "$task_id" "$workdir" "$agent_json"; then
    sample_failures=$((sample_failures + 1))
    echo "frontier agent failed for $task_id" >&2
    exit 1
  fi
  if ! extract_final_diff "$agent_json" "$prediction_jsonl" "$task_id"; then
    sample_failures=$((sample_failures + 1))
    exit 1
  fi
  if ! score_prediction "$task_id" "$prediction_jsonl" "$RUN_ID" "$score_log"; then
    score_failures=$((score_failures + 1))
    echo "official scorer failed for $task_id" >&2
    exit 1
  fi
  resolved="$(score_resolved "$score_log")" || {
    score_failures=$((score_failures + 1))
    exit 1
  }
  freeze_args+=("--task" "$task_id" "$prediction_jsonl" "$score_log")
  printf 'frontier_task=%s resolved=%s prediction_sha256=%s score_sha256=%s\n' \
    "$task_id" "$resolved" "$(sha256_file "$prediction_jsonl")" "$(sha256_file "$score_log")"
done

if ! "$SWE_PYTHON" "$FREEZER" "${freeze_args[@]}"; then
  echo "frontier baseline freezer failed" >&2
  exit 1
fi

receipt_ok=false
if baseline_receipt_ok "$OUT_BASELINE" "${TASKS[@]}"; then
  receipt_ok=true
else
  echo "frontier baseline evidence receipt was rejected by elevation stream gate" >&2
  exit 1
fi

task_hash="$(tasks_hash "${TASKS[@]}")"
task_provenance_sha256="$(task_provenance_sha256 "${TASKS[@]}")"
write_summary "$OUTDIR/frontier_baseline_summary.json" "$OUT_BASELINE" "$receipt_ok" "$task_provenance_ok" "$task_provenance_sha256" "$suite_preflight_ok" "$sample_failures" "$score_failures" "$task_hash" "$DATASET_NAME" "$BENCHMARK_SUITE" "$FRONTIER_MODEL" "${TASKS[@]}"

printf 'metric=frontier_baseline_receipt metric_claim=false official_benchmark=true tasks=%s frontier_baseline_path=%s frontier_baseline_evidence_receipt_ok=%s sample_failures=%s score_failures=%s summary=%s\n' \
  "${#TASKS[@]}" "$OUT_BASELINE" "$receipt_ok" "$sample_failures" "$score_failures" "$OUTDIR/frontier_baseline_summary.json"
