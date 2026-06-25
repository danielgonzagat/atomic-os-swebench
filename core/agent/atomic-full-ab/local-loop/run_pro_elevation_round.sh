#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWE_PYTHON="${ATOMIC_PRO_ELEVATION_PYTHON:-/opt/homebrew/bin/python3}"
MANIFEST="${ATOMIC_PRO_ELEVATION_MANIFEST:-$HERE/elevation_pro_suite_manifest.json}"
WEIGHTS="${ATOMIC_PRO_ELEVATION_WEIGHTS:-$HERE/.corpus/weights.jsonl}"
FRONTIER_RUNNER="${ATOMIC_PRO_FRONTIER_RUNNER:-$HERE/run_frontier_baseline.sh}"
ELEVATION_STREAM="${ATOMIC_PRO_ELEVATION_STREAM:-$HERE/run_elevation_stream.sh}"
OUTROOT="${ATOMIC_PRO_ELEVATION_OUTROOT:-$HERE/evidence/PRO_ELEVATION_ROUND}"
BENCHMARK_SUITE="swe_bench_pro"
DATASET_NAME="ScaleAI/SWE-bench_Pro"

usage() {
  cat >&2 <<'USAGE'
Usage:
  run_pro_elevation_round.sh --selftest
  run_pro_elevation_round.sh --preflight [OUT_JSON]
  run_pro_elevation_round.sh --ready [OUT_JSON]
  run_pro_elevation_round.sh --verify-preflight PREFLIGHT_JSON
  run_pro_elevation_round.sh --verify-round-receipt ROUND_RECEIPT_JSON
  run_pro_elevation_round.sh [RUN_TAG]

Runs the official Pro Elevação sequence from the held-out manifest:
frontier+Atomic baseline receipt -> receipt selftest -> elevation stream.
Secrets must be supplied through environment variables; no API key is accepted on
argv or in code.
USAGE
}

sanitize() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

sha256_text() {
  "$SWE_PYTHON" - "$@" <<'PYHASH'
import hashlib
import sys
print(hashlib.sha256("\n".join(sys.argv[1:]).encode()).hexdigest())
PYHASH
}

sha256_file() {
  "$SWE_PYTHON" - "$1" <<'PYHASHFILE'
import hashlib
import sys
with open(sys.argv[1], "rb") as handle:
    print(hashlib.sha256(handle.read()).hexdigest())
PYHASHFILE
}

sha256_file_if_present() {
  if [[ -f "$1" ]]; then
    sha256_file "$1"
  fi
}

manifest_report() {
  "$SWE_PYTHON" - "$MANIFEST" <<'PYREPORT'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"manifest_error={type(exc).__name__}:{exc}")
    sys.exit(0)
tasks = data.get("selected_task_ids") or []
if not isinstance(tasks, list):
    tasks = []
official = (
    data.get("benchmark_suite") == "swe_bench_pro"
    and data.get("dataset_name") == "ScaleAI/SWE-bench_Pro"
    and (data.get("benchmark_label") in (None, "SWE-bench-Pro"))
    and data.get("official_benchmark") is not False
)
print(f"benchmark_suite={data.get('benchmark_suite', '')}")
print(f"benchmark_dataset_name={data.get('dataset_name', '')}")
print(f"official_benchmark={'true' if official else 'false'}")
print(f"selected_task_count={len(tasks)}")
for task in tasks:
    print(f"task_id={task}")
PYREPORT
}

load_tasks() {
  "$SWE_PYTHON" - "$MANIFEST" <<'PYTASKS'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
for task in data.get("selected_task_ids") or []:
    if isinstance(task, str) and task:
        print(task)
PYTASKS
}

manifest_is_official() {
  manifest_report | grep -q '^official_benchmark=true$'
}

emit_selftest() {
  local report selected_count official suite dataset task_hash frontier_runner_sha256 elevation_stream_sha256
  report="$(manifest_report)"
  selected_count="$(printf '%s\n' "$report" | awk -F= '/^selected_task_count=/{print $2}' | tail -1)"
  official="$(printf '%s\n' "$report" | awk -F= '/^official_benchmark=/{print $2}' | tail -1)"
  suite="$(printf '%s\n' "$report" | awk -F= '/^benchmark_suite=/{print $2}' | tail -1)"
  dataset="$(printf '%s\n' "$report" | awk -F= '/^benchmark_dataset_name=/{print $2}' | tail -1)"
  task_hash="$(sha256_text $(printf '%s\n' "$report" | awk -F= '/^task_id=/{print $2}'))"
  frontier_runner_sha256="$(sha256_file_if_present "$FRONTIER_RUNNER")"
  elevation_stream_sha256="$(sha256_file_if_present "$ELEVATION_STREAM")"
  cat <<EOF
metric=pro_elevation_round
metric_claim=false
benchmark_suite=$suite
benchmark_dataset_name=$dataset
official_benchmark=$official
manifest_path=$MANIFEST
selected_task_count=${selected_count:-0}
selected_task_ids_sha256=$task_hash
requires_deepseek_api_key=true
credential_source=env
credential_file_allowed=false
frontier_baseline_runner=$FRONTIER_RUNNER
frontier_baseline_runner_sha256=$frontier_runner_sha256
elevation_stream=$ELEVATION_STREAM
elevation_stream_sha256=$elevation_stream_sha256
weights_path=$WEIGHTS
no_synthetic=true
no_replay=true
summary_fields=metric,run_id,metric_claim,benchmark_suite,benchmark_dataset_name,official_benchmark,manifest_path,selected_task_count,frontier_baseline_runner,frontier_baseline_runner_sha256,elevation_stream,elevation_stream_sha256,weights_path,weights_sha256,preflight_receipt_path,preflight_receipt_sha256,preflight_verification_ok,task_provenance_ok,task_provenance_sha256,frontier_baseline_path,frontier_baseline_sha256,frontier_baseline_evidence_receipt_ok,elevation_valid_if_run,elevation_summary_path,elevation_summary_sha256,round_receipt_path,round_receipt_sha256,round_receipt_verification_ok
EOF
}

report_field() {
  local report="$1"
  local key="$2"
  local default="${3:-}"
  local value
  value="$(printf '%s\n' "$report" | awk -F= -v key="$key" '$1 == key {print $2}' | tail -1)"
  printf '%s\n' "${value:-$default}"
}

write_preflight_json() {
  local out_json="$1"
  shift
  mkdir -p "$(dirname "$out_json")"
  "$SWE_PYTHON" - "$out_json" "$@" <<'PYPREFLIGHT'
import json
import sys

out_path = sys.argv[1]
payload = {}
for item in sys.argv[2:]:
    key, raw = item.split("=", 1)
    if raw == "true":
        value = True
    elif raw == "false":
        value = False
    elif raw.isdigit():
        value = int(raw)
    else:
        value = raw
    payload[key] = value
with open(out_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYPREFLIGHT
}

write_round_receipt_json() {
  local out_json="$1"
  shift
  mkdir -p "$(dirname "$out_json")"
  "$SWE_PYTHON" - "$out_json" "$@" <<'PYROUNDRECEIPT'
import json
import sys

out_path = sys.argv[1]
args = sys.argv[2:]
try:
    marker = args.index("--tasks")
except ValueError:
    marker = len(args)
kv_items = args[:marker]
tasks = args[marker + 1 :] if marker < len(args) else []
payload = {}
for item in kv_items:
    key, raw = item.split("=", 1)
    if raw == "true":
        value = True
    elif raw == "false":
        value = False
    elif raw.isdigit():
        value = int(raw)
    else:
        value = raw
    payload[key] = value
payload["task_ids"] = tasks
with open(out_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYROUNDRECEIPT
}

emit_ready() {
  local report ready
  report="$(emit_preflight "${1:-}")"
  printf '%s\n' "$report"
  ready="$(report_field "$report" ready_to_run false)"
  [[ "$ready" == "true" ]]
}

emit_preflight() {
  local out_json="${1:-${ATOMIC_PRO_PREFLIGHT_OUT:-}}"
  local report selected_count official suite dataset task_hash
  local deepseek_present frontier_runner_ok elevation_stream_ok weights_ok
  local frontier_runner_sha256 elevation_stream_sha256
  local task_layout task_provenance task_provenance_sha suite_pristine_layout ready frontier_report preflight_receipt_path
  local tasks=()

  report="$(manifest_report)"
  selected_count="$(report_field "$report" selected_task_count 0)"
  official="$(report_field "$report" official_benchmark false)"
  suite="$(report_field "$report" benchmark_suite '')"
  dataset="$(report_field "$report" benchmark_dataset_name '')"
  while IFS= read -r task; do
    [[ -n "$task" ]] && tasks+=("$task")
  done < <(printf '%s\n' "$report" | awk -F= '/^task_id=/{print $2}')
  task_hash="$(sha256_text "${tasks[@]}")"

  deepseek_present=false
  [[ -n "${DEEPSEEK_API_KEY:-}" ]] && deepseek_present=true
  frontier_runner_ok=false
  [[ -x "$FRONTIER_RUNNER" ]] && frontier_runner_ok=true
  elevation_stream_ok=false
  [[ -x "$ELEVATION_STREAM" ]] && elevation_stream_ok=true
  frontier_runner_sha256="$(sha256_file_if_present "$FRONTIER_RUNNER")"
  elevation_stream_sha256="$(sha256_file_if_present "$ELEVATION_STREAM")"
  weights_ok=false
  [[ -f "$WEIGHTS" ]] && weights_ok=true

  task_layout=false
  task_provenance=false
  task_provenance_sha=""
  suite_pristine_layout=false
  if [[ "$frontier_runner_ok" == "true" && "${#tasks[@]}" -gt 0 ]]; then
    frontier_report="$($FRONTIER_RUNNER --selftest "${tasks[@]}" 2>/dev/null || true)"
    task_layout="$(report_field "$frontier_report" task_layout_ok false)"
    task_provenance="$(report_field "$frontier_report" task_provenance_ok false)"
    task_provenance_sha="$(report_field "$frontier_report" task_provenance_sha256 '')"
    suite_pristine_layout="$(report_field "$frontier_report" suite_pristine_layout_ok false)"
  fi

  ready=false
  if [[ "$official" == "true" \
    && "$selected_count" =~ ^[1-9][0-9]*$ \
    && "$deepseek_present" == "true" \
    && "$frontier_runner_ok" == "true" \
    && "$elevation_stream_ok" == "true" \
    && "$weights_ok" == "true" \
    && "$task_layout" == "true" \
    && "$task_provenance" == "true" \
    && "$task_provenance_sha" =~ ^[0-9a-f]{64}$ \
    && "$suite_pristine_layout" == "true" ]]; then
    ready=true
  fi

  preflight_receipt_path="$out_json"
  cat <<EOF
metric=pro_elevation_preflight
metric_claim=false
benchmark_suite=$suite
benchmark_dataset_name=$dataset
official_benchmark=$official
manifest_path=$MANIFEST
selected_task_count=${selected_count:-0}
selected_task_ids_sha256=$task_hash
deepseek_api_key_present=$deepseek_present
credential_source=env
credential_file_allowed=false
frontier_runner_ok=$frontier_runner_ok
frontier_baseline_runner=$FRONTIER_RUNNER
frontier_baseline_runner_sha256=$frontier_runner_sha256
elevation_stream_ok=$elevation_stream_ok
elevation_stream=$ELEVATION_STREAM
elevation_stream_sha256=$elevation_stream_sha256
weights_ok=$weights_ok
task_layout_ok=$task_layout
task_provenance_ok=$task_provenance
task_provenance_sha256=$task_provenance_sha
suite_pristine_layout_ok=$suite_pristine_layout
ready_to_run=$ready
no_model_run=true
no_scorer_run=true
preflight_receipt_path=$preflight_receipt_path
EOF

  if [[ -n "$out_json" ]]; then
    write_preflight_json "$out_json" \
      metric=pro_elevation_preflight \
      metric_claim=false \
      benchmark_suite="$suite" \
      benchmark_dataset_name="$dataset" \
      official_benchmark="$official" \
      manifest_path="$MANIFEST" \
      selected_task_count="${selected_count:-0}" \
      selected_task_ids_sha256="$task_hash" \
      deepseek_api_key_present="$deepseek_present" \
      credential_source=env \
      credential_file_allowed=false \
      frontier_runner_ok="$frontier_runner_ok" \
      frontier_baseline_runner="$FRONTIER_RUNNER" \
      frontier_baseline_runner_sha256="$frontier_runner_sha256" \
      elevation_stream_ok="$elevation_stream_ok" \
      elevation_stream="$ELEVATION_STREAM" \
      elevation_stream_sha256="$elevation_stream_sha256" \
      weights_ok="$weights_ok" \
      task_layout_ok="$task_layout" \
      task_provenance_ok="$task_provenance" \
      task_provenance_sha256="$task_provenance_sha" \
      suite_pristine_layout_ok="$suite_pristine_layout" \
      ready_to_run="$ready" \
      no_model_run=true \
      no_scorer_run=true
  fi
}

verify_preflight_receipt() {
  local receipt_json="${1:-}"
  local current_report
  if [[ -z "$receipt_json" || ! -f "$receipt_json" ]]; then
    cat <<EOF
metric=pro_elevation_preflight_verification
metric_claim=false
preflight_receipt_path=$receipt_json
preflight_receipt_exists=false
preflight_receipt_schema_ok=false
receipt_ready_to_run=false
current_ready_to_run=false
receipt_matches_current=false
preflight_receipt_ok=false
no_model_run=true
no_scorer_run=true
EOF
    return 2
  fi

  current_report="$(emit_preflight "")"
  "$SWE_PYTHON" - "$receipt_json" "$current_report" <<'PYPREVERIFY'
import json
import sys

receipt_path, current_report = sys.argv[1:3]
required = [
    "metric",
    "metric_claim",
    "benchmark_suite",
    "benchmark_dataset_name",
    "official_benchmark",
    "manifest_path",
    "selected_task_count",
    "selected_task_ids_sha256",
    "deepseek_api_key_present",
    "credential_source",
    "credential_file_allowed",
    "frontier_runner_ok",
    "frontier_baseline_runner",
    "frontier_baseline_runner_sha256",
    "elevation_stream_ok",
    "elevation_stream",
    "elevation_stream_sha256",
    "weights_ok",
    "task_layout_ok",
    "task_provenance_ok",
    "task_provenance_sha256",
    "suite_pristine_layout_ok",
    "ready_to_run",
    "no_model_run",
    "no_scorer_run",
]


def normalize(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if value is None:
        return ""
    return str(value)


def parse_report(text):
    parsed = {}
    for line in text.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            parsed[key] = value
    return parsed

current = parse_report(current_report)
try:
    with open(receipt_path, encoding="utf-8") as handle:
        receipt = json.load(handle)
except Exception:
    receipt = {}

missing = [key for key in required if key not in receipt]
receipt_values = {key: normalize(receipt.get(key, "")) for key in required}
schema_ok = not missing
schema_ok = schema_ok and receipt_values.get("metric") == "pro_elevation_preflight"
schema_ok = schema_ok and receipt_values.get("metric_claim") == "false"
schema_ok = schema_ok and receipt_values.get("credential_source") == "env"
schema_ok = schema_ok and receipt_values.get("credential_file_allowed") == "false"
schema_ok = schema_ok and receipt_values.get("no_model_run") == "true"
schema_ok = schema_ok and receipt_values.get("no_scorer_run") == "true"
provenance_sha = receipt_values.get("task_provenance_sha256", "")
provenance_sha_ok = len(provenance_sha) == 64 and all(char in "0123456789abcdef" for char in provenance_sha)
schema_ok = schema_ok and (receipt_values.get("ready_to_run") != "true" or provenance_sha_ok)
receipt_ready = receipt_values.get("ready_to_run") == "true"
current_ready = current.get("ready_to_run") == "true"
matches_current = schema_ok and all(receipt_values.get(key, "") == current.get(key, "") for key in required)
receipt_ok = schema_ok and receipt_ready and current_ready and matches_current

print("metric=pro_elevation_preflight_verification")
print("metric_claim=false")
print(f"preflight_receipt_path={receipt_path}")
print("preflight_receipt_exists=true")
print(f"preflight_receipt_schema_ok={'true' if schema_ok else 'false'}")
print(f"preflight_receipt_missing_fields={','.join(missing)}")
print(f"receipt_ready_to_run={'true' if receipt_ready else 'false'}")
print(f"current_ready_to_run={'true' if current_ready else 'false'}")
print(f"receipt_matches_current={'true' if matches_current else 'false'}")
print(f"preflight_receipt_ok={'true' if receipt_ok else 'false'}")
print("no_model_run=true")
print("no_scorer_run=true")
raise SystemExit(0 if receipt_ok else 2)
PYPREVERIFY
}

elevation_summary_from_log() {
  local log_path="$1"
  local fallback_path="$2"
  local summary_path
  summary_path="$(awk -F= '/^elevation_summary=/{print $2}' "$log_path" | tail -1)"
  if [[ -z "$summary_path" ]]; then
    summary_path="$(awk '/^Elevation summary: /{sub(/^Elevation summary: /, ""); print}' "$log_path" | tail -1)"
  fi
  if [[ -z "$summary_path" ]]; then
    summary_path="$fallback_path"
  fi
  case "$summary_path" in
    /*) printf '%s\n' "$summary_path" ;;
    *) printf '%s/%s\n' "$HERE" "$summary_path" ;;
  esac
}

validate_elevation_summary() {
  local summary_path="$1"
  shift
  "$SWE_PYTHON" - "$summary_path" "$BENCHMARK_SUITE" "$DATASET_NAME" "$@" <<'PYSUMMARYCHECK'
import json
import sys

path, benchmark_suite, dataset_name, *tasks = sys.argv[1:]
try:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
except Exception as exc:
    print(f"summary_json_error={type(exc).__name__}:{exc}", file=sys.stderr)
    raise SystemExit(2)

summary_tasks = data.get("task_ids")
required_true_fields = (
    "elevation_valid",
    "task_provenance_ok",
    "suite_preflight_ok",
    "frontier_baseline_evidence_receipt_ok",
    "frontier_baseline_provenance_ok",
    "teacher_atomic",
    "anti_replay",
    "distinct_tasks",
)
ok = (
    isinstance(data, dict)
    and data.get("metric") == "elevation"
    and data.get("benchmark_suite") == benchmark_suite
    and data.get("benchmark_dataset_name") == dataset_name
    and data.get("official_benchmark") is True
    and isinstance(summary_tasks, list)
    and summary_tasks == tasks
    and all(data.get(field) is True for field in required_true_fields)
)
if not ok:
    print("summary_json_contract=false", file=sys.stderr)
    raise SystemExit(2)
PYSUMMARYCHECK
}

verify_round_receipt() {
  local receipt_json="${1:-}"
  if [[ -z "$receipt_json" || ! -f "$receipt_json" ]]; then
    cat <<EOF
metric=pro_elevation_round_receipt_verification
metric_claim=false
round_receipt_path=$receipt_json
round_receipt_exists=false
round_receipt_schema_ok=false
round_receipt_artifact_hashes_ok=false
round_receipt_task_ids_ok=false
round_receipt_ok=false
no_model_run=true
no_scorer_run=true
EOF
    return 2
  fi

  "$SWE_PYTHON" - "$receipt_json" <<'PYROUNDVERIFY'
import hashlib
import json
import sys
from pathlib import Path

receipt_path = Path(sys.argv[1])
required = [
    "metric",
    "metric_claim",
    "run_id",
    "benchmark_suite",
    "benchmark_dataset_name",
    "official_benchmark",
    "manifest_path",
    "selected_task_count",
    "selected_task_ids_sha256",
    "frontier_baseline_runner",
    "frontier_baseline_runner_sha256",
    "elevation_stream",
    "elevation_stream_sha256",
    "weights_path",
    "weights_sha256",
    "preflight_receipt_path",
    "preflight_receipt_sha256",
    "preflight_verification_ok",
    "task_provenance_ok",
    "task_provenance_sha256",
    "frontier_baseline_path",
    "frontier_baseline_sha256",
    "frontier_baseline_evidence_receipt_ok",
    "elevation_valid_if_run",
    "elevation_summary_path",
    "elevation_summary_sha256",
    "round_receipt_path",
    "task_ids",
]


def sha256_file(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def sha256_text(items):
    return hashlib.sha256("\n".join(items).encode()).hexdigest()

try:
    with receipt_path.open(encoding="utf-8") as handle:
        receipt = json.load(handle)
except Exception:
    receipt = {}

missing = [key for key in required if key not in receipt] if isinstance(receipt, dict) else required
schema_ok = isinstance(receipt, dict) and not missing
schema_ok = schema_ok and receipt.get("metric") == "pro_elevation_round"
schema_ok = schema_ok and receipt.get("metric_claim") is False
schema_ok = schema_ok and receipt.get("benchmark_suite") == "swe_bench_pro"
schema_ok = schema_ok and receipt.get("benchmark_dataset_name") == "ScaleAI/SWE-bench_Pro"
schema_ok = schema_ok and receipt.get("official_benchmark") is True
schema_ok = schema_ok and receipt.get("preflight_verification_ok") is True
schema_ok = schema_ok and receipt.get("task_provenance_ok") is True
schema_ok = schema_ok and receipt.get("frontier_baseline_evidence_receipt_ok") is True
schema_ok = schema_ok and receipt.get("elevation_valid_if_run") is True
provenance_sha = receipt.get("task_provenance_sha256")
provenance_sha_ok = isinstance(provenance_sha, str) and len(provenance_sha) == 64 and all(char in "0123456789abcdef" for char in provenance_sha)
preflight_provenance_ok = False
preflight_path_value = receipt.get("preflight_receipt_path")
if isinstance(preflight_path_value, str):
    preflight_path = Path(preflight_path_value)
    if preflight_path.is_file():
        try:
            with preflight_path.open(encoding="utf-8") as handle:
                preflight = json.load(handle)
            preflight_provenance_ok = preflight.get("task_provenance_ok") is True and preflight.get("task_provenance_sha256") == provenance_sha
        except Exception:
            preflight_provenance_ok = False
schema_ok = schema_ok and provenance_sha_ok and preflight_provenance_ok

hash_pairs = [
    ("frontier_baseline_runner", "frontier_baseline_runner_sha256"),
    ("elevation_stream", "elevation_stream_sha256"),
    ("weights_path", "weights_sha256"),
    ("preflight_receipt_path", "preflight_receipt_sha256"),
    ("frontier_baseline_path", "frontier_baseline_sha256"),
    ("elevation_summary_path", "elevation_summary_sha256"),
]
artifact_hashes_ok = schema_ok
for path_key, hash_key in hash_pairs:
    path_value = receipt.get(path_key)
    expected_hash = receipt.get(hash_key)
    if not isinstance(path_value, str) or not isinstance(expected_hash, str):
        artifact_hashes_ok = False
        continue
    path = Path(path_value)
    if not path.is_file():
        artifact_hashes_ok = False
        continue
    if sha256_file(path) != expected_hash:
        artifact_hashes_ok = False

tasks = receipt.get("task_ids")
try:
    selected_count = int(receipt.get("selected_task_count"))
except Exception:
    selected_count = -1
task_ids_ok = (
    isinstance(tasks, list)
    and all(isinstance(task, str) and task for task in tasks)
    and selected_count == len(tasks)
    and isinstance(receipt.get("selected_task_ids_sha256"), str)
    and sha256_text(tasks) == receipt.get("selected_task_ids_sha256")
)

receipt_sha256 = sha256_file(receipt_path)
receipt_ok = schema_ok and artifact_hashes_ok and task_ids_ok

print("metric=pro_elevation_round_receipt_verification")
print("metric_claim=false")
print(f"round_receipt_path={receipt_path}")
print("round_receipt_exists=true")
print(f"round_receipt_sha256={receipt_sha256}")
print(f"round_receipt_schema_ok={'true' if schema_ok else 'false'}")
print(f"round_receipt_missing_fields={','.join(missing)}")
print(f"round_receipt_artifact_hashes_ok={'true' if artifact_hashes_ok else 'false'}")
print(f"round_receipt_task_ids_ok={'true' if task_ids_ok else 'false'}")
print(f"round_receipt_ok={'true' if receipt_ok else 'false'}")
print("no_model_run=true")
print("no_scorer_run=true")
raise SystemExit(0 if receipt_ok else 2)
PYROUNDVERIFY
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--selftest" ]]; then
  emit_selftest
  exit 0
fi

if [[ "${1:-}" == "--preflight" ]]; then
  shift
  emit_preflight "${1:-}"
  exit 0
fi

if [[ "${1:-}" == "--ready" ]]; then
  shift
  emit_ready "${1:-}"
  exit $?
fi

if [[ "${1:-}" == "--verify-preflight" ]]; then
  shift
  verify_preflight_receipt "${1:-}"
  exit $?
fi

if [[ "${1:-}" == "--verify-round-receipt" ]]; then
  shift
  verify_round_receipt "${1:-}"
  exit $?
fi

RUN_TAG="${1:-${ATOMIC_PRO_ELEVATION_RUN_TAG:-PROELEV}}"

if ! manifest_is_official; then
  echo "official SWE-Bench Pro manifest required: $MANIFEST" >&2
  exit 2
fi

TASKS=()
while IFS= read -r task; do
  [[ -n "$task" ]] && TASKS+=("$task")
done < <(load_tasks)
selected_task_ids_sha256="$(sha256_text "${TASKS[@]}")"
if [[ "${#TASKS[@]}" -eq 0 ]]; then
  echo "Pro elevation manifest has no selected_task_ids: $MANIFEST" >&2
  exit 2
fi

RUN_ID="${ATOMIC_PRO_ELEVATION_RUN_ID:-pro_elevation_$(sanitize "$RUN_TAG")_T${#TASKS[@]}_$(date -u +%Y%m%dT%H%M%SZ)_$$}"
OUTDIR="$OUTROOT/$RUN_ID"
BASELINE="$OUTDIR/frontier_baseline.json"
PREFLIGHT="$OUTDIR/preflight.json"
ROUND_RECEIPT="$OUTDIR/round_receipt.json"
mkdir -p "$OUTDIR"

preflight_report="$(emit_preflight "$PREFLIGHT")"
preflight_ready="$(report_field "$preflight_report" ready_to_run false)"
if [[ "$preflight_ready" != "true" ]]; then
  echo "Pro elevation preflight failed; refusing model/scorer round" >&2
  printf '%s\n' "$preflight_report" >&2
  exit 2
fi

if ! preflight_verification="$(verify_preflight_receipt "$PREFLIGHT")"; then
  echo "Pro elevation preflight receipt verification failed; refusing model/scorer round" >&2
  printf '%s\n' "$preflight_verification" >&2
  exit 2
fi
preflight_verification_ok="$(report_field "$preflight_verification" preflight_receipt_ok false)"
if [[ "$preflight_verification_ok" != "true" ]]; then
  echo "Pro elevation preflight receipt verification did not prove readiness" >&2
  printf '%s\n' "$preflight_verification" >&2
  exit 2
fi
task_provenance_ok="$(report_field "$preflight_report" task_provenance_ok false)"
task_provenance_sha256="$(report_field "$preflight_report" task_provenance_sha256 '')"
preflight_receipt_sha256="$(sha256_file "$PREFLIGHT")"
frontier_runner_sha256="$(sha256_file "$FRONTIER_RUNNER")"
elevation_stream_sha256="$(sha256_file "$ELEVATION_STREAM")"

echo "=== PRO ELEVATION ROUND $RUN_ID ==="
echo "manifest=$MANIFEST"
echo "tasks=${TASKS[*]}"
echo "preflight_receipt_path=$PREFLIGHT"
echo "preflight_verification_ok=$preflight_verification_ok"
echo "task_provenance_sha256=$task_provenance_sha256"
echo "frontier_baseline_runner=$FRONTIER_RUNNER"
echo "frontier_baseline_runner_sha256=$frontier_runner_sha256"
echo "elevation_stream=$ELEVATION_STREAM"
echo "elevation_stream_sha256=$elevation_stream_sha256"
echo "frontier_baseline_path=$BASELINE"

"$FRONTIER_RUNNER" "$RUN_ID-frontier" "$BASELINE" "${TASKS[@]}"

stream_selftest="$("$ELEVATION_STREAM" --selftest "$WEIGHTS" "$BASELINE" "${TASKS[@]}")"
frontier_receipt_ok="$(printf '%s\n' "$stream_selftest" | awk -F= '/^frontier_baseline_evidence_receipt_ok=/{print $2}' | tail -1)"
elevation_valid_if_run="$(printf '%s\n' "$stream_selftest" | awk -F= '/^elevation_valid_if_run=/{print $2}' | tail -1)"
if [[ "$frontier_receipt_ok" != "true" || "$elevation_valid_if_run" != "true" ]]; then
  echo "frontier receipt/elevation selftest rejected the just-frozen baseline" >&2
  printf '%s\n' "$stream_selftest" >&2
  exit 2
fi
frontier_baseline_sha256="$(sha256_file "$BASELINE")"
weights_sha256="$(sha256_file "$WEIGHTS")"

ATOMIC_ELEVATION_RUN_ID="$RUN_ID" "$ELEVATION_STREAM" "$RUN_TAG" "$BASELINE" "$WEIGHTS" "${TASKS[@]}" | tee "$OUTDIR/elevation_stream.log"

elevation_summary_path="$(elevation_summary_from_log "$OUTDIR/elevation_stream.log" "$HERE/evidence/ELEVATION/$RUN_ID/elevation_summary.json")"
if ! validate_elevation_summary "$elevation_summary_path" "${TASKS[@]}"; then
  echo "elevation summary missing or invalid: $elevation_summary_path" >&2
  exit 2
fi
elevation_summary_sha256="$(sha256_file "$elevation_summary_path")"
write_round_receipt_json "$ROUND_RECEIPT" \
  metric=pro_elevation_round \
  metric_claim=false \
  run_id="$RUN_ID" \
  benchmark_suite="$BENCHMARK_SUITE" \
  benchmark_dataset_name="$DATASET_NAME" \
  official_benchmark=true \
  manifest_path="$MANIFEST" \
  selected_task_count="${#TASKS[@]}" \
  selected_task_ids_sha256="$selected_task_ids_sha256" \
  frontier_baseline_runner="$FRONTIER_RUNNER" \
  frontier_baseline_runner_sha256="$frontier_runner_sha256" \
  elevation_stream="$ELEVATION_STREAM" \
  elevation_stream_sha256="$elevation_stream_sha256" \
  weights_path="$WEIGHTS" \
  weights_sha256="$weights_sha256" \
  preflight_receipt_path="$PREFLIGHT" \
  preflight_receipt_sha256="$preflight_receipt_sha256" \
  preflight_verification_ok="$preflight_verification_ok" \
  task_provenance_ok="$task_provenance_ok" \
  frontier_baseline_path="$BASELINE" \
  frontier_baseline_sha256="$frontier_baseline_sha256" \
  frontier_baseline_evidence_receipt_ok="$frontier_receipt_ok" \
  elevation_valid_if_run="$elevation_valid_if_run" \
  elevation_summary_path="$elevation_summary_path" \
  elevation_summary_sha256="$elevation_summary_sha256" \
  round_receipt_path="$ROUND_RECEIPT" \
  --tasks "${TASKS[@]}"
round_receipt_sha256="$(sha256_file "$ROUND_RECEIPT")"
if ! round_receipt_verification="$(verify_round_receipt "$ROUND_RECEIPT")"; then
  echo "Pro elevation round receipt verification failed; refusing final metric line" >&2
  printf '%s\n' "$round_receipt_verification" >&2
  exit 2
fi
round_receipt_verification_ok="$(report_field "$round_receipt_verification" round_receipt_ok false)"
if [[ "$round_receipt_verification_ok" != "true" ]]; then
  echo "Pro elevation round receipt did not prove itself" >&2
  printf '%s\n' "$round_receipt_verification" >&2
  exit 2
fi
printf 'metric=pro_elevation_round metric_claim=false run_id=%s benchmark_suite=%s benchmark_dataset_name=%s official_benchmark=true manifest_path=%s selected_task_count=%s selected_task_ids_sha256=%s frontier_baseline_runner=%s frontier_baseline_runner_sha256=%s elevation_stream=%s elevation_stream_sha256=%s weights_path=%s weights_sha256=%s preflight_receipt_path=%s preflight_receipt_sha256=%s preflight_verification_ok=%s task_provenance_ok=%s frontier_baseline_path=%s frontier_baseline_sha256=%s frontier_baseline_evidence_receipt_ok=%s elevation_valid_if_run=%s elevation_summary_path=%s elevation_summary_sha256=%s round_receipt_path=%s round_receipt_sha256=%s round_receipt_verification_ok=%s\n' \
  "$RUN_ID" "$BENCHMARK_SUITE" "$DATASET_NAME" "$MANIFEST" "${#TASKS[@]}" "$selected_task_ids_sha256" "$FRONTIER_RUNNER" "$frontier_runner_sha256" "$ELEVATION_STREAM" "$elevation_stream_sha256" "$WEIGHTS" "$weights_sha256" "$PREFLIGHT" "$preflight_receipt_sha256" "$preflight_verification_ok" "$task_provenance_ok" "$BASELINE" "$frontier_baseline_sha256" "$frontier_receipt_ok" "$elevation_valid_if_run" "$elevation_summary_path" "$elevation_summary_sha256" "$ROUND_RECEIPT" "$round_receipt_sha256" "$round_receipt_verification_ok"
