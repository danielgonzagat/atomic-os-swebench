#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWE_PYTHON="${ATOMIC_PRO_ELEVATION_PYTHON:-/opt/homebrew/bin/python3}"
MANIFEST="${ATOMIC_PRO_ELEVATION_MANIFEST:-$HERE/elevation_pro_suite_manifest.json}"
WEIGHTS="${ATOMIC_PRO_ELEVATION_WEIGHTS:-$HERE/.corpus/weights.jsonl}"
CANONICAL_FRONTIER_RUNNER="$HERE/run_frontier_baseline.sh"
CANONICAL_ELEVATION_STREAM="$HERE/run_elevation_stream.sh"
FRONTIER_RUNNER="${ATOMIC_PRO_FRONTIER_RUNNER:-$CANONICAL_FRONTIER_RUNNER}"
ELEVATION_STREAM="${ATOMIC_PRO_ELEVATION_STREAM:-$CANONICAL_ELEVATION_STREAM}"
OUTROOT="${ATOMIC_PRO_ELEVATION_OUTROOT:-$HERE/evidence/PRO_ELEVATION_ROUND}"
BENCHMARK_SUITE="swe_bench_pro"
DATASET_NAME="ScaleAI/SWE-bench_Pro"
STUDENT_MODEL="deepseek-v4-pro"
METRIC_SCOPE="paired_frontier_solve_rate_delta"
WITHIN_TASK_EFFICIENCY_METRIC_ADMISSIBLE=false

usage() {
  cat >&2 <<'USAGE'
Usage:
  run_pro_elevation_round.sh --selftest
  run_pro_elevation_round.sh --preflight [OUT_JSON]
  run_pro_elevation_round.sh --ready [OUT_JSON]
  run_pro_elevation_round.sh --production-ready [OUT_JSON]
  run_pro_elevation_round.sh --verify-preflight PREFLIGHT_JSON
  run_pro_elevation_round.sh --verify-production-ready PREFLIGHT_JSON
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

realpath_file() {
  "$SWE_PYTHON" - "$1" <<'PYREALPATH'
import os
import sys
print(os.path.realpath(sys.argv[1]))
PYREALPATH
}

same_realpath() {
  [[ -e "$1" && -e "$2" ]] || return 1
  [[ "$(realpath_file "$1")" == "$(realpath_file "$2")" ]]
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
rows = data.get("rows")
teach = data.get("teach_task_ids")
anti = data.get("anti_leakage") or {}
method = data.get("selection_method") or ""
row_ids = [r.get("instance_id") for r in rows] if isinstance(rows, list) and all(isinstance(r, dict) for r in rows) else []
counts_ok = (
    isinstance(data.get("total_count"), int)
    and isinstance(data.get("eligible_count"), int)
    and isinstance(data.get("selected_count"), int)
    and data["total_count"] >= data["eligible_count"] >= data["selected_count"] > 0
)
ids_ok = (
    isinstance(tasks, list)
    and bool(tasks)
    and len(tasks) == len(set(tasks))
    and data.get("selected_count") == len(tasks)
    and row_ids == tasks
)
rows_ok = isinstance(rows, list) and all(
    isinstance(r, dict)
    and isinstance(r.get("instance_id"), str)
    and isinstance(r.get("selection_rank_sha256"), str)
    and r.get("selection_rank_sha256")
    and "problem_statement" not in r
    and "patch" not in r
    and "test_patch" not in r
    for r in rows
)
teach_ok = isinstance(teach, list) and all(isinstance(t, str) and t for t in teach) and set(tasks).isdisjoint(teach)
anti_leakage_ok = (
    anti.get("problem_statement") == "omitted"
    and anti.get("patch") == "omitted"
    and anti.get("test_patch") == "omitted"
)
selection_ok = (
    data.get("metric_claim") is False
    and data.get("purpose") == "held_out_candidate_manifest_not_elevation_result"
    and data.get("dataset_split") == "test"
    and isinstance(data.get("selection_seed"), str)
    and bool(data.get("selection_seed"))
    and "sha256" in method
    and "excludes teach task ids" in method
    and counts_ok
    and ids_ok
    and rows_ok
    and teach_ok
    and anti_leakage_ok
)
print(f"benchmark_suite={data.get('benchmark_suite', '')}")
print(f"benchmark_dataset_name={data.get('dataset_name', '')}")
print(f"official_benchmark={'true' if official else 'false'}")
print(f"selected_task_count={len(tasks)}")
print(f"selection_receipt_ok={'true' if selection_ok else 'false'}")
print(f"anti_cherry_pick={'true' if selection_ok else 'false'}")
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
  local report selected_count official suite dataset task_hash selection_manifest_sha256 frontier_runner_sha256 elevation_stream_sha256 selection_receipt_ok anti_cherry_pick
  report="$(manifest_report)"
  selected_count="$(printf '%s\n' "$report" | awk -F= '/^selected_task_count=/{print $2}' | tail -1)"
  official="$(printf '%s\n' "$report" | awk -F= '/^official_benchmark=/{print $2}' | tail -1)"
  suite="$(printf '%s\n' "$report" | awk -F= '/^benchmark_suite=/{print $2}' | tail -1)"
  dataset="$(printf '%s\n' "$report" | awk -F= '/^benchmark_dataset_name=/{print $2}' | tail -1)"
  selection_receipt_ok="$(printf '%s\n' "$report" | awk -F= '/^selection_receipt_ok=/{print $2}' | tail -1)"
  anti_cherry_pick="$(printf '%s\n' "$report" | awk -F= '/^anti_cherry_pick=/{print $2}' | tail -1)"
  task_hash="$(sha256_text $(printf '%s\n' "$report" | awk -F= '/^task_id=/{print $2}'))"
  selection_manifest_sha256="$(sha256_file_if_present "$MANIFEST")"
  frontier_runner_sha256="$(sha256_file_if_present "$FRONTIER_RUNNER")"
  elevation_stream_sha256="$(sha256_file_if_present "$ELEVATION_STREAM")"
  cat <<EOF
metric=pro_elevation_round
metric_claim=false
benchmark_suite=$suite
benchmark_dataset_name=$dataset
official_benchmark=$official
metric_scope=$METRIC_SCOPE
within_task_efficiency_metric_admissible=$WITHIN_TASK_EFFICIENCY_METRIC_ADMISSIBLE
manifest_path=$MANIFEST
selected_task_count=${selected_count:-0}
selected_task_ids_sha256=$task_hash
selection_manifest_path=$MANIFEST
selection_manifest_sha256=$selection_manifest_sha256
selection_receipt_ok=${selection_receipt_ok:-false}
anti_cherry_pick=${anti_cherry_pick:-false}
metric_scope=$METRIC_SCOPE
within_task_efficiency_metric_admissible=$WITHIN_TASK_EFFICIENCY_METRIC_ADMISSIBLE
requires_deepseek_api_key=true
requires_modal_token_id=true
requires_modal_token_secret=true
requires_rotated_credentials_attestation=true
credential_source=env
credential_file_allowed=false
frontier_baseline_runner=$FRONTIER_RUNNER
frontier_baseline_runner_sha256=$frontier_runner_sha256
elevation_stream=$ELEVATION_STREAM
elevation_stream_sha256=$elevation_stream_sha256
weights_path=$WEIGHTS
no_synthetic=true
no_replay=true
summary_fields=metric,run_id,metric_claim,production_ready_to_run,ready_blockers,production_ready_blockers,metric_admissible,production_toolchain_ok,benchmark_suite,benchmark_dataset_name,official_benchmark,metric_scope,within_task_efficiency_metric_admissible,manifest_path,selected_task_count,selected_task_ids_sha256,selection_manifest_path,selection_manifest_sha256,selection_receipt_ok,anti_cherry_pick,frontier_baseline_runner,frontier_baseline_runner_sha256,elevation_stream,elevation_stream_sha256,weights_path,weights_sha256,preflight_receipt_path,preflight_receipt_sha256,preflight_verification_ok,task_provenance_ok,task_provenance_sha256,frontier_baseline_path,frontier_baseline_sha256,frontier_model,frontier_baseline_role,frontier_baseline_frozen,frontier_baseline_official_docker,frontier_baseline_benchmark_label,frontier_baseline_summary_path,frontier_baseline_summary_sha256,frontier_summary_verification_ok,frontier_baseline_evidence_receipt_ok,frontier_baseline_resolved,frontier_solve_rate,deepseek_control_resolved,deepseek_control_solve_rate,atomic_substrate_resolved,student_solve_rate,student_model,elevation_vs_frontier,elevation_vs_frontier_solve_rate,elevation_vs_deepseek_control,elevation_vs_deepseek_control_solve_rate,accumulation_index,substrate_weight_count,elevation_valid_if_run,elevation_summary_path,elevation_summary_sha256,round_receipt_path,round_receipt_sha256,round_receipt_verification_ok
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
import re
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
    elif re.fullmatch(r"-?\d+", raw):
        value = int(raw)
    elif re.fullmatch(r"-?\d+\.\d+(?:[eE]-?\d+)?", raw):
        value = float(raw)
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

emit_production_ready() {
  local report production_ready
  report="$(emit_preflight "${1:-}")"
  printf '%s\n' "$report"
  production_ready="$(report_field "$report" production_ready_to_run false)"
  [[ "$production_ready" == "true" ]]
}

check_swebench_import() {
  "$SWE_PYTHON" - <<'PYSWEBENCHPREFLIGHT' >/dev/null 2>&1
import importlib.util
import sys

if importlib.util.find_spec("swebench.harness.run_evaluation") is None:
    sys.exit(1)
PYSWEBENCHPREFLIGHT
}

check_docker_api() {
  "$SWE_PYTHON" - "${ATOMIC_PRO_DOCKER_TIMEOUT_SECONDS:-20}" <<'PYDOCKERPREFLIGHT' >/dev/null 2>&1
import subprocess
import sys

timeout = int(sys.argv[1])
subprocess.check_output(
    ["docker", "version", "--format", "{{.Server.Version}}"],
    stderr=subprocess.STDOUT,
    text=True,
    timeout=timeout,
)
PYDOCKERPREFLIGHT
}

check_deepseek_api_key_format() {
  [[ "${DEEPSEEK_API_KEY:-}" =~ ^sk-[A-Za-z0-9]{32,}$ ]]
}

check_modal_token_id_format() {
  [[ "${MODAL_TOKEN_ID:-}" =~ ^ak-[A-Za-z0-9_-]{12,}$ ]]
}

check_modal_token_secret_format() {
  [[ "${MODAL_TOKEN_SECRET:-}" =~ ^as-[A-Za-z0-9_-]{12,}$ ]]
}

check_modal_cli_present() {
  command -v modal >/dev/null 2>&1
}

modal_token_probe_report() {
  "$SWE_PYTHON" - "${ATOMIC_PRO_MODAL_TIMEOUT_SECONDS:-20}" <<'PYMODALPREFLIGHT'
import os
import subprocess
import sys

timeout = float(sys.argv[1])
auth_ok = False
if os.environ.get("MODAL_TOKEN_ID") and os.environ.get("MODAL_TOKEN_SECRET"):
    try:
        completed = subprocess.run(
            ["modal", "token", "info"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
            check=False,
        )
        auth_ok = completed.returncode == 0
    except Exception:
        pass
print(f"modal_auth_ok={'true' if auth_ok else 'false'}")
PYMODALPREFLIGHT
}

deepseek_api_probe_report() {
  "$SWE_PYTHON" - "${ATOMIC_PRO_DEEPSEEK_BALANCE_URL:-https://api.deepseek.com/user/balance}" "${ATOMIC_PRO_DEEPSEEK_TIMEOUT_SECONDS:-15}" <<'PYDEEPSEEKPREFLIGHT'
import json
import os
import sys
import urllib.error
import urllib.request

url, raw_timeout = sys.argv[1:3]
timeout = float(raw_timeout)
token = os.environ.get("DEEPSEEK_API_KEY", "")
auth_ok = False
balance_available = False
if token:
    try:
        request = urllib.request.Request(
            url,
            headers={
                "Accept": "application/json",
                "Authorization": f"Bearer {token}",
            },
            method="GET",
        )
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status = response.getcode()
            payload = response.read(1024 * 1024)
        if 200 <= status < 300:
            auth_ok = True
            try:
                data = json.loads(payload.decode("utf-8"))
            except Exception:
                data = {}
            balance_available = data.get("is_available") is True
    except urllib.error.HTTPError as exc:
        if exc.code == 402:
            auth_ok = True
    except Exception:
        pass
print(f"deepseek_auth_ok={'true' if auth_ok else 'false'}")
print(f"deepseek_balance_available={'true' if balance_available else 'false'}")
PYDEEPSEEKPREFLIGHT
}

emit_preflight() {
  local out_json="${1:-${ATOMIC_PRO_PREFLIGHT_OUT:-}}"
  local report selected_count official suite dataset task_hash
  local selection_receipt_ok anti_cherry_pick selection_manifest_sha256
  local deepseek_present modal_token_id_present modal_token_secret_present modal_credentials_present frontier_runner_ok elevation_stream_ok weights_ok
  local deepseek_api_key_format_ok modal_token_id_format_ok modal_token_secret_format_ok modal_credentials_format_ok
  local credential_format_bypassed_by_test_runner credential_format_ok production_credential_format_ok
  local credential_rotation_attested credential_rotation_attestation_bypassed_by_test_runner credential_rotation_attestation_ok
  local deepseek_probe_report deepseek_auth_ok deepseek_balance_available official_deepseek_api_preflight_ok deepseek_api_preflight_ok deepseek_api_preflight_bypassed_by_test_runner
  local modal_probe_report modal_cli_present modal_auth_ok official_modal_preflight_ok modal_preflight_ok modal_preflight_bypassed_by_test_runner
  local canonical_toolchain test_runner_override_allowed runner_policy_ok
  local swebench_import_ok docker_api_ok official_scorer_preflight_ok scorer_preflight_ok scorer_preflight_bypassed_by_test_runner
  local frontier_runner_sha256 elevation_stream_sha256
  local task_layout task_provenance task_provenance_sha suite_pristine_layout ready production_ready frontier_report preflight_receipt_path
  local tasks=()

  report="$(manifest_report)"
  selected_count="$(report_field "$report" selected_task_count 0)"
  official="$(report_field "$report" official_benchmark false)"
  suite="$(report_field "$report" benchmark_suite '')"
  dataset="$(report_field "$report" benchmark_dataset_name '')"
  selection_receipt_ok="$(report_field "$report" selection_receipt_ok false)"
  anti_cherry_pick="$(report_field "$report" anti_cherry_pick false)"
  while IFS= read -r task; do
    [[ -n "$task" ]] && tasks+=("$task")
  done < <(printf '%s\n' "$report" | awk -F= '/^task_id=/{print $2}')
  task_hash="$(sha256_text "${tasks[@]}")"
  selection_manifest_sha256="$(sha256_file_if_present "$MANIFEST")"

  deepseek_present=false
  [[ -n "${DEEPSEEK_API_KEY:-}" ]] && deepseek_present=true
  modal_token_id_present=false
  [[ -n "${MODAL_TOKEN_ID:-}" ]] && modal_token_id_present=true
  modal_token_secret_present=false
  [[ -n "${MODAL_TOKEN_SECRET:-}" ]] && modal_token_secret_present=true
  modal_credentials_present=false
  if [[ "$modal_token_id_present" == "true" && "$modal_token_secret_present" == "true" ]]; then
    modal_credentials_present=true
  fi
  deepseek_api_key_format_ok=false
  check_deepseek_api_key_format && deepseek_api_key_format_ok=true
  modal_token_id_format_ok=false
  check_modal_token_id_format && modal_token_id_format_ok=true
  modal_token_secret_format_ok=false
  check_modal_token_secret_format && modal_token_secret_format_ok=true
  modal_credentials_format_ok=false
  if [[ "$modal_token_id_format_ok" == "true" && "$modal_token_secret_format_ok" == "true" ]]; then
    modal_credentials_format_ok=true
  fi
  production_credential_format_ok=false
  if [[ "$deepseek_api_key_format_ok" == "true" && "$modal_credentials_format_ok" == "true" ]]; then
    production_credential_format_ok=true
  fi
  frontier_runner_ok=false
  [[ -x "$FRONTIER_RUNNER" ]] && frontier_runner_ok=true
  elevation_stream_ok=false
  [[ -x "$ELEVATION_STREAM" ]] && elevation_stream_ok=true
  frontier_runner_sha256="$(sha256_file_if_present "$FRONTIER_RUNNER")"
  elevation_stream_sha256="$(sha256_file_if_present "$ELEVATION_STREAM")"
  weights_ok=false
  [[ -f "$WEIGHTS" ]] && weights_ok=true
  canonical_toolchain=false
  if same_realpath "$FRONTIER_RUNNER" "$CANONICAL_FRONTIER_RUNNER" && same_realpath "$ELEVATION_STREAM" "$CANONICAL_ELEVATION_STREAM"; then
    canonical_toolchain=true
  fi
  test_runner_override_allowed=false
  [[ "${ATOMIC_PRO_ELEVATION_ALLOW_TEST_RUNNERS:-}" == "1" ]] && test_runner_override_allowed=true
  credential_rotation_attested=false
  [[ "${ATOMIC_PRO_CREDENTIALS_ROTATED:-}" == "1" ]] && credential_rotation_attested=true
  credential_rotation_attestation_bypassed_by_test_runner=false
  [[ "$test_runner_override_allowed" == "true" ]] && credential_rotation_attestation_bypassed_by_test_runner=true
  credential_rotation_attestation_ok=false
  if [[ "$credential_rotation_attested" == "true" || "$credential_rotation_attestation_bypassed_by_test_runner" == "true" ]]; then
    credential_rotation_attestation_ok=true
  fi
  credential_format_bypassed_by_test_runner=false
  [[ "$test_runner_override_allowed" == "true" ]] && credential_format_bypassed_by_test_runner=true
  credential_format_ok=false
  if [[ "$production_credential_format_ok" == "true" || "$credential_format_bypassed_by_test_runner" == "true" ]]; then
    credential_format_ok=true
  fi
  deepseek_auth_ok=false
  deepseek_balance_available=false
  official_deepseek_api_preflight_ok=false
  deepseek_api_preflight_ok=false
  deepseek_api_preflight_bypassed_by_test_runner=false
  if [[ "$test_runner_override_allowed" == "true" ]]; then
    deepseek_api_preflight_bypassed_by_test_runner=true
    deepseek_api_preflight_ok=true
  elif [[ "$deepseek_api_key_format_ok" == "true" ]]; then
    deepseek_probe_report="$(deepseek_api_probe_report)"
    deepseek_auth_ok="$(report_field "$deepseek_probe_report" deepseek_auth_ok false)"
    deepseek_balance_available="$(report_field "$deepseek_probe_report" deepseek_balance_available false)"
    if [[ "$deepseek_auth_ok" == "true" && "$deepseek_balance_available" == "true" ]]; then
      official_deepseek_api_preflight_ok=true
      deepseek_api_preflight_ok=true
    fi
  fi
  modal_cli_present=false
  check_modal_cli_present && modal_cli_present=true
  modal_auth_ok=false
  official_modal_preflight_ok=false
  modal_preflight_ok=false
  modal_preflight_bypassed_by_test_runner=false
  if [[ "$test_runner_override_allowed" == "true" ]]; then
    modal_preflight_bypassed_by_test_runner=true
    modal_preflight_ok=true
  elif [[ "$modal_credentials_format_ok" == "true" && "$modal_cli_present" == "true" ]]; then
    modal_probe_report="$(modal_token_probe_report)"
    modal_auth_ok="$(report_field "$modal_probe_report" modal_auth_ok false)"
    if [[ "$modal_auth_ok" == "true" ]]; then
      official_modal_preflight_ok=true
      modal_preflight_ok=true
    fi
  fi
  runner_policy_ok=false
  if [[ "$canonical_toolchain" == "true" || "$test_runner_override_allowed" == "true" ]]; then
    runner_policy_ok=true
  fi
  swebench_import_ok=false
  docker_api_ok=false
  official_scorer_preflight_ok=false
  scorer_preflight_ok=false
  scorer_preflight_bypassed_by_test_runner=false
  if [[ "$test_runner_override_allowed" == "true" ]]; then
    scorer_preflight_bypassed_by_test_runner=true
    scorer_preflight_ok=true
  else
    check_swebench_import && swebench_import_ok=true
    check_docker_api && docker_api_ok=true
    if [[ "$swebench_import_ok" == "true" && "$docker_api_ok" == "true" ]]; then
      official_scorer_preflight_ok=true
      scorer_preflight_ok=true
    fi
  fi

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

  selected_count_ok=false
  if [[ "$selected_count" =~ ^[1-9][0-9]*$ ]]; then
    selected_count_ok=true
  fi
  task_provenance_sha_ok=false
  if [[ "$task_provenance_sha" =~ ^[0-9a-f]{64}$ ]]; then
    task_provenance_sha_ok=true
  fi

  ready_blockers=""
  add_ready_blocker() {
    if [[ "$1" != "true" ]]; then
      if [[ -n "$ready_blockers" ]]; then
        ready_blockers+=","
      fi
      ready_blockers+="$2"
    fi
  }
  add_ready_blocker "$official" official_benchmark
  add_ready_blocker "$selected_count_ok" selected_task_count
  add_ready_blocker "$selection_receipt_ok" selection_receipt_ok
  add_ready_blocker "$anti_cherry_pick" anti_cherry_pick
  add_ready_blocker "$deepseek_present" deepseek_api_key_present
  add_ready_blocker "$modal_credentials_present" modal_credentials_present
  add_ready_blocker "$credential_format_ok" credential_format_ok
  add_ready_blocker "$credential_rotation_attestation_ok" credential_rotation_attestation_ok
  add_ready_blocker "$deepseek_api_preflight_ok" deepseek_api_preflight_ok
  add_ready_blocker "$modal_preflight_ok" modal_preflight_ok
  add_ready_blocker "$scorer_preflight_ok" scorer_preflight_ok
  add_ready_blocker "$runner_policy_ok" runner_policy_ok
  add_ready_blocker "$frontier_runner_ok" frontier_runner_ok
  add_ready_blocker "$elevation_stream_ok" elevation_stream_ok
  add_ready_blocker "$weights_ok" weights_ok
  add_ready_blocker "$task_layout" task_layout_ok
  add_ready_blocker "$task_provenance" task_provenance_ok
  add_ready_blocker "$task_provenance_sha_ok" task_provenance_sha256
  add_ready_blocker "$suite_pristine_layout" suite_pristine_layout_ok

  ready=false
  if [[ -z "$ready_blockers" ]]; then
    ready=true
  fi

  test_runner_override_disabled=false
  if [[ "$test_runner_override_allowed" == "false" ]]; then
    test_runner_override_disabled=true
  fi
  production_ready_blockers=""
  add_production_ready_blocker() {
    if [[ "$1" != "true" ]]; then
      if [[ -n "$production_ready_blockers" ]]; then
        production_ready_blockers+=","
      fi
      production_ready_blockers+="$2"
    fi
  }
  add_production_ready_blocker "$ready" ready_to_run
  add_production_ready_blocker "$canonical_toolchain" canonical_toolchain
  add_production_ready_blocker "$test_runner_override_disabled" test_runner_override_allowed
  add_production_ready_blocker "$production_credential_format_ok" production_credential_format_ok
  add_production_ready_blocker "$credential_rotation_attested" credential_rotation_attested
  add_production_ready_blocker "$official_deepseek_api_preflight_ok" official_deepseek_api_preflight_ok
  add_production_ready_blocker "$official_modal_preflight_ok" official_modal_preflight_ok
  add_production_ready_blocker "$official_scorer_preflight_ok" official_scorer_preflight_ok
  add_production_ready_blocker "$runner_policy_ok" runner_policy_ok

  production_ready=false
  if [[ -z "$production_ready_blockers" ]]; then
    production_ready=true
  fi

  preflight_receipt_path="$out_json"
  cat <<EOF
metric=pro_elevation_preflight
metric_claim=false
benchmark_suite=$suite
benchmark_dataset_name=$dataset
official_benchmark=$official
metric_scope=$METRIC_SCOPE
within_task_efficiency_metric_admissible=$WITHIN_TASK_EFFICIENCY_METRIC_ADMISSIBLE
manifest_path=$MANIFEST
selected_task_count=${selected_count:-0}
selected_task_ids_sha256=$task_hash
selection_manifest_path=$MANIFEST
selection_manifest_sha256=$selection_manifest_sha256
selection_receipt_ok=$selection_receipt_ok
anti_cherry_pick=$anti_cherry_pick
deepseek_api_key_present=$deepseek_present
modal_token_id_present=$modal_token_id_present
modal_token_secret_present=$modal_token_secret_present
modal_credentials_present=$modal_credentials_present
deepseek_api_key_format_ok=$deepseek_api_key_format_ok
modal_token_id_format_ok=$modal_token_id_format_ok
modal_token_secret_format_ok=$modal_token_secret_format_ok
modal_credentials_format_ok=$modal_credentials_format_ok
credential_format_bypassed_by_test_runner=$credential_format_bypassed_by_test_runner
credential_format_ok=$credential_format_ok
production_credential_format_ok=$production_credential_format_ok
credential_rotation_attested=$credential_rotation_attested
credential_rotation_attestation_bypassed_by_test_runner=$credential_rotation_attestation_bypassed_by_test_runner
credential_rotation_attestation_ok=$credential_rotation_attestation_ok
deepseek_auth_ok=$deepseek_auth_ok
deepseek_balance_available=$deepseek_balance_available
official_deepseek_api_preflight_ok=$official_deepseek_api_preflight_ok
deepseek_api_preflight_ok=$deepseek_api_preflight_ok
deepseek_api_preflight_bypassed_by_test_runner=$deepseek_api_preflight_bypassed_by_test_runner
modal_cli_present=$modal_cli_present
modal_auth_ok=$modal_auth_ok
official_modal_preflight_ok=$official_modal_preflight_ok
modal_preflight_ok=$modal_preflight_ok
modal_preflight_bypassed_by_test_runner=$modal_preflight_bypassed_by_test_runner
credential_source=env
credential_file_allowed=false
canonical_toolchain=$canonical_toolchain
test_runner_override_allowed=$test_runner_override_allowed
runner_policy_ok=$runner_policy_ok
swebench_import_ok=$swebench_import_ok
docker_api_ok=$docker_api_ok
official_scorer_preflight_ok=$official_scorer_preflight_ok
scorer_preflight_ok=$scorer_preflight_ok
scorer_preflight_bypassed_by_test_runner=$scorer_preflight_bypassed_by_test_runner
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
production_ready_to_run=$production_ready
ready_blockers=$ready_blockers
production_ready_blockers=$production_ready_blockers
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
      metric_scope="$METRIC_SCOPE" \
      within_task_efficiency_metric_admissible="$WITHIN_TASK_EFFICIENCY_METRIC_ADMISSIBLE" \
      manifest_path="$MANIFEST" \
      selected_task_count="${selected_count:-0}" \
      selected_task_ids_sha256="$task_hash" \
      selection_manifest_path="$MANIFEST" \
      selection_manifest_sha256="$selection_manifest_sha256" \
      selection_receipt_ok="$selection_receipt_ok" \
      anti_cherry_pick="$anti_cherry_pick" \
      deepseek_api_key_present="$deepseek_present" \
      modal_token_id_present="$modal_token_id_present" \
      modal_token_secret_present="$modal_token_secret_present" \
      modal_credentials_present="$modal_credentials_present" \
      deepseek_api_key_format_ok="$deepseek_api_key_format_ok" \
      modal_token_id_format_ok="$modal_token_id_format_ok" \
      modal_token_secret_format_ok="$modal_token_secret_format_ok" \
      modal_credentials_format_ok="$modal_credentials_format_ok" \
      credential_format_bypassed_by_test_runner="$credential_format_bypassed_by_test_runner" \
      credential_format_ok="$credential_format_ok" \
      production_credential_format_ok="$production_credential_format_ok" \
      credential_rotation_attested="$credential_rotation_attested" \
      credential_rotation_attestation_bypassed_by_test_runner="$credential_rotation_attestation_bypassed_by_test_runner" \
      credential_rotation_attestation_ok="$credential_rotation_attestation_ok" \
      deepseek_auth_ok="$deepseek_auth_ok" \
      deepseek_balance_available="$deepseek_balance_available" \
      official_deepseek_api_preflight_ok="$official_deepseek_api_preflight_ok" \
      deepseek_api_preflight_ok="$deepseek_api_preflight_ok" \
      deepseek_api_preflight_bypassed_by_test_runner="$deepseek_api_preflight_bypassed_by_test_runner" \
      modal_cli_present="$modal_cli_present" \
      modal_auth_ok="$modal_auth_ok" \
      official_modal_preflight_ok="$official_modal_preflight_ok" \
      modal_preflight_ok="$modal_preflight_ok" \
      modal_preflight_bypassed_by_test_runner="$modal_preflight_bypassed_by_test_runner" \
      credential_source=env \
      credential_file_allowed=false \
      canonical_toolchain="$canonical_toolchain" \
      test_runner_override_allowed="$test_runner_override_allowed" \
      runner_policy_ok="$runner_policy_ok" \
      swebench_import_ok="$swebench_import_ok" \
      docker_api_ok="$docker_api_ok" \
      official_scorer_preflight_ok="$official_scorer_preflight_ok" \
      scorer_preflight_ok="$scorer_preflight_ok" \
      scorer_preflight_bypassed_by_test_runner="$scorer_preflight_bypassed_by_test_runner" \
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
      production_ready_to_run="$production_ready" \
      ready_blockers="$ready_blockers" \
      production_ready_blockers="$production_ready_blockers" \
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
preflight_receipt_missing_fields=
preflight_receipt_schema_issue_paths=preflight_receipt_exists
receipt_ready_to_run=false
current_ready_to_run=false
receipt_production_ready_to_run=false
current_production_ready_to_run=false
ready_blockers=preflight_receipt_exists
production_ready_blockers=preflight_receipt_ok
preflight_receipt_mismatch_paths=preflight_receipt_exists
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
    "metric_scope",
    "within_task_efficiency_metric_admissible",
    "manifest_path",
    "selected_task_count",
    "selected_task_ids_sha256",
    "selection_manifest_path",
    "selection_manifest_sha256",
    "selection_receipt_ok",
    "anti_cherry_pick",
    "deepseek_api_key_present",
    "modal_token_id_present",
    "modal_token_secret_present",
    "modal_credentials_present",
    "deepseek_api_key_format_ok",
    "modal_token_id_format_ok",
    "modal_token_secret_format_ok",
    "modal_credentials_format_ok",
    "credential_format_bypassed_by_test_runner",
    "credential_format_ok",
    "production_credential_format_ok",
    "credential_rotation_attested",
    "credential_rotation_attestation_bypassed_by_test_runner",
    "credential_rotation_attestation_ok",
    "deepseek_auth_ok",
    "deepseek_balance_available",
    "official_deepseek_api_preflight_ok",
    "deepseek_api_preflight_ok",
    "deepseek_api_preflight_bypassed_by_test_runner",
    "modal_cli_present",
    "modal_auth_ok",
    "official_modal_preflight_ok",
    "modal_preflight_ok",
    "modal_preflight_bypassed_by_test_runner",
    "credential_source",
    "credential_file_allowed",
    "canonical_toolchain",
    "test_runner_override_allowed",
    "runner_policy_ok",
    "swebench_import_ok",
    "docker_api_ok",
    "official_scorer_preflight_ok",
    "scorer_preflight_ok",
    "scorer_preflight_bypassed_by_test_runner",
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
    "production_ready_to_run",
    "ready_blockers",
    "production_ready_blockers",
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
receipt_parse_issue = ""
try:
    with open(receipt_path, encoding="utf-8") as handle:
        receipt = json.load(handle)
except Exception:
    receipt = {}
    receipt_parse_issue = "preflight_receipt_json"
if not isinstance(receipt, dict):
    receipt = {}
    receipt_parse_issue = "preflight_receipt_object"

missing = [] if receipt_parse_issue else [key for key in required if key not in receipt]
schema_issue_paths = [receipt_parse_issue] if receipt_parse_issue else list(missing)
receipt_values = {key: normalize(receipt.get(key, "")) for key in required}
schema_ok = not missing
schema_ok = schema_ok and receipt_values.get("metric") == "pro_elevation_preflight"
schema_ok = schema_ok and receipt_values.get("metric_claim") == "false"
schema_ok = schema_ok and receipt_values.get("metric_scope") == "paired_frontier_solve_rate_delta"
schema_ok = schema_ok and receipt_values.get("within_task_efficiency_metric_admissible") == "false"
schema_ok = schema_ok and receipt_values.get("credential_source") == "env"
schema_ok = schema_ok and receipt_values.get("credential_file_allowed") == "false"
schema_ok = schema_ok and receipt_values.get("runner_policy_ok") == "true"
schema_ok = schema_ok and receipt_values.get("no_model_run") == "true"
schema_ok = schema_ok and receipt_values.get("no_scorer_run") == "true"
schema_ok = schema_ok and receipt_values.get("modal_token_id_present") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("modal_token_secret_present") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("modal_credentials_present") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("selection_receipt_ok") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("anti_cherry_pick") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("deepseek_api_key_format_ok") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("modal_token_id_format_ok") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("modal_token_secret_format_ok") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("modal_credentials_format_ok") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("credential_format_bypassed_by_test_runner") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("credential_format_ok") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("production_credential_format_ok") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("credential_rotation_attested") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("credential_rotation_attestation_bypassed_by_test_runner") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("credential_rotation_attestation_ok") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("deepseek_auth_ok") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("deepseek_balance_available") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("official_deepseek_api_preflight_ok") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("deepseek_api_preflight_ok") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("deepseek_api_preflight_bypassed_by_test_runner") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("modal_cli_present") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("modal_auth_ok") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("official_modal_preflight_ok") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("modal_preflight_ok") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("modal_preflight_bypassed_by_test_runner") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("modal_credentials_present") == (
    "true" if (
        receipt_values.get("modal_token_id_present") == "true"
        and receipt_values.get("modal_token_secret_present") == "true"
    ) else "false"
)
schema_ok = schema_ok and receipt_values.get("modal_credentials_format_ok") == (
    "true" if (
        receipt_values.get("modal_token_id_format_ok") == "true"
        and receipt_values.get("modal_token_secret_format_ok") == "true"
    ) else "false"
)
schema_ok = schema_ok and receipt_values.get("production_credential_format_ok") == (
    "true" if (
        receipt_values.get("deepseek_api_key_format_ok") == "true"
        and receipt_values.get("modal_credentials_format_ok") == "true"
    ) else "false"
)
schema_ok = schema_ok and (
    receipt_values.get("credential_format_bypassed_by_test_runner") != "true"
    or receipt_values.get("test_runner_override_allowed") == "true"
)
expected_credential_format_ok = (
    "true" if (
        receipt_values.get("production_credential_format_ok") == "true"
        or receipt_values.get("credential_format_bypassed_by_test_runner") == "true"
    ) else "false"
)
credential_format_schema_ok = receipt_values.get("credential_format_ok") == expected_credential_format_ok
schema_ok = schema_ok and credential_format_schema_ok
if not credential_format_schema_ok and "credential_format_ok" not in schema_issue_paths:
    schema_issue_paths.append("credential_format_ok")
schema_ok = schema_ok and (
    receipt_values.get("credential_rotation_attestation_bypassed_by_test_runner") != "true"
    or receipt_values.get("test_runner_override_allowed") == "true"
)
expected_credential_rotation_attestation_ok = (
    "true" if (
        receipt_values.get("credential_rotation_attested") == "true"
        or receipt_values.get("credential_rotation_attestation_bypassed_by_test_runner") == "true"
    ) else "false"
)
credential_rotation_attestation_schema_ok = receipt_values.get("credential_rotation_attestation_ok") == expected_credential_rotation_attestation_ok
schema_ok = schema_ok and credential_rotation_attestation_schema_ok
if not credential_rotation_attestation_schema_ok and "credential_rotation_attestation_ok" not in schema_issue_paths:
    schema_issue_paths.append("credential_rotation_attestation_ok")
schema_ok = schema_ok and receipt_values.get("official_deepseek_api_preflight_ok") == (
    "true" if (
        receipt_values.get("deepseek_auth_ok") == "true"
        and receipt_values.get("deepseek_balance_available") == "true"
    ) else "false"
)
schema_ok = schema_ok and (
    receipt_values.get("deepseek_api_preflight_bypassed_by_test_runner") != "true"
    or receipt_values.get("test_runner_override_allowed") == "true"
)
expected_deepseek_api_preflight_ok = (
    "true" if (
        receipt_values.get("official_deepseek_api_preflight_ok") == "true"
        or receipt_values.get("deepseek_api_preflight_bypassed_by_test_runner") == "true"
    ) else "false"
)
deepseek_api_preflight_schema_ok = receipt_values.get("deepseek_api_preflight_ok") == expected_deepseek_api_preflight_ok
schema_ok = schema_ok and deepseek_api_preflight_schema_ok
if not deepseek_api_preflight_schema_ok and "deepseek_api_preflight_ok" not in schema_issue_paths:
    schema_issue_paths.append("deepseek_api_preflight_ok")
schema_ok = schema_ok and receipt_values.get("official_modal_preflight_ok") == (
    "true" if (
        receipt_values.get("modal_cli_present") == "true"
        and receipt_values.get("modal_auth_ok") == "true"
    ) else "false"
)
schema_ok = schema_ok and (
    receipt_values.get("modal_preflight_bypassed_by_test_runner") != "true"
    or receipt_values.get("test_runner_override_allowed") == "true"
)
expected_modal_preflight_ok = (
    "true" if (
        receipt_values.get("official_modal_preflight_ok") == "true"
        or receipt_values.get("modal_preflight_bypassed_by_test_runner") == "true"
    ) else "false"
)
modal_preflight_schema_ok = receipt_values.get("modal_preflight_ok") == expected_modal_preflight_ok
schema_ok = schema_ok and modal_preflight_schema_ok
if not modal_preflight_schema_ok and "modal_preflight_ok" not in schema_issue_paths:
    schema_issue_paths.append("modal_preflight_ok")
schema_ok = schema_ok and receipt_values.get("swebench_import_ok") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("docker_api_ok") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("official_scorer_preflight_ok") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("scorer_preflight_ok") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("scorer_preflight_bypassed_by_test_runner") in ("true", "false")
schema_ok = schema_ok and receipt_values.get("official_scorer_preflight_ok") == (
    "true" if (
        receipt_values.get("swebench_import_ok") == "true"
        and receipt_values.get("docker_api_ok") == "true"
    ) else "false"
)
expected_scorer_preflight_ok = (
    "true" if (
        receipt_values.get("official_scorer_preflight_ok") == "true"
        or receipt_values.get("scorer_preflight_bypassed_by_test_runner") == "true"
    ) else "false"
)
scorer_preflight_schema_ok = receipt_values.get("scorer_preflight_ok") == expected_scorer_preflight_ok
schema_ok = schema_ok and scorer_preflight_schema_ok
if not scorer_preflight_schema_ok and "scorer_preflight_ok" not in schema_issue_paths:
    schema_issue_paths.append("scorer_preflight_ok")
schema_ok = schema_ok and (
    receipt_values.get("scorer_preflight_bypassed_by_test_runner") != "true"
    or receipt_values.get("test_runner_override_allowed") == "true"
)
provenance_sha = receipt_values.get("task_provenance_sha256", "")
provenance_sha_ok = len(provenance_sha) == 64 and all(char in "0123456789abcdef" for char in provenance_sha)
expected_receipt_ready = (
    provenance_sha_ok
    and receipt_values.get("selection_receipt_ok") == "true"
    and receipt_values.get("anti_cherry_pick") == "true"
    and receipt_values.get("deepseek_api_key_present") == "true"
    and receipt_values.get("modal_credentials_present") == "true"
    and receipt_values.get("credential_format_ok") == "true"
    and receipt_values.get("credential_rotation_attestation_ok") == "true"
    and receipt_values.get("deepseek_api_preflight_ok") == "true"
    and receipt_values.get("modal_preflight_ok") == "true"
    and receipt_values.get("scorer_preflight_ok") == "true"
)
receipt_ready = receipt_values.get("ready_to_run") == "true"
ready_schema_ok = receipt_ready == expected_receipt_ready
schema_ok = schema_ok and ready_schema_ok
if not ready_schema_ok and "ready_to_run" not in schema_issue_paths:
    schema_issue_paths.append("ready_to_run")
current_ready = current.get("ready_to_run") == "true"
receipt_production_ready = receipt_values.get("production_ready_to_run") == "true"
current_production_ready = current.get("production_ready_to_run") == "true"
expected_receipt_production_ready = (
    receipt_ready
    and receipt_values.get("canonical_toolchain") == "true"
    and receipt_values.get("test_runner_override_allowed") == "false"
    and receipt_values.get("production_credential_format_ok") == "true"
    and receipt_values.get("credential_rotation_attested") == "true"
    and receipt_values.get("official_deepseek_api_preflight_ok") == "true"
    and receipt_values.get("official_modal_preflight_ok") == "true"
    and receipt_values.get("official_scorer_preflight_ok") == "true"
    and receipt_values.get("runner_policy_ok") == "true"
)
production_ready_schema_ok = receipt_production_ready == expected_receipt_production_ready
schema_ok = schema_ok and production_ready_schema_ok
if not production_ready_schema_ok and "production_ready_to_run" not in schema_issue_paths:
    schema_issue_paths.append("production_ready_to_run")
schema_ok = schema_ok and isinstance(receipt.get("ready_blockers"), str)
schema_ok = schema_ok and isinstance(receipt.get("production_ready_blockers"), str)


def blocker_list(checks):
    return ",".join(name for ok, name in checks if not ok)


try:
    selected_count_ok = int(receipt_values.get("selected_task_count", "0")) > 0
except ValueError:
    selected_count_ok = False
expected_ready_blockers = blocker_list([
    (receipt_values.get("official_benchmark") == "true", "official_benchmark"),
    (selected_count_ok, "selected_task_count"),
    (receipt_values.get("selection_receipt_ok") == "true", "selection_receipt_ok"),
    (receipt_values.get("anti_cherry_pick") == "true", "anti_cherry_pick"),
    (receipt_values.get("deepseek_api_key_present") == "true", "deepseek_api_key_present"),
    (receipt_values.get("modal_credentials_present") == "true", "modal_credentials_present"),
    (receipt_values.get("credential_format_ok") == "true", "credential_format_ok"),
    (receipt_values.get("credential_rotation_attestation_ok") == "true", "credential_rotation_attestation_ok"),
    (receipt_values.get("deepseek_api_preflight_ok") == "true", "deepseek_api_preflight_ok"),
    (receipt_values.get("modal_preflight_ok") == "true", "modal_preflight_ok"),
    (receipt_values.get("scorer_preflight_ok") == "true", "scorer_preflight_ok"),
    (receipt_values.get("runner_policy_ok") == "true", "runner_policy_ok"),
    (receipt_values.get("frontier_runner_ok") == "true", "frontier_runner_ok"),
    (receipt_values.get("elevation_stream_ok") == "true", "elevation_stream_ok"),
    (receipt_values.get("weights_ok") == "true", "weights_ok"),
    (receipt_values.get("task_layout_ok") == "true", "task_layout_ok"),
    (receipt_values.get("task_provenance_ok") == "true", "task_provenance_ok"),
    (provenance_sha_ok, "task_provenance_sha256"),
    (receipt_values.get("suite_pristine_layout_ok") == "true", "suite_pristine_layout_ok"),
])
expected_production_ready_blockers = blocker_list([
    (receipt_ready, "ready_to_run"),
    (receipt_values.get("canonical_toolchain") == "true", "canonical_toolchain"),
    (receipt_values.get("test_runner_override_allowed") == "false", "test_runner_override_allowed"),
    (receipt_values.get("production_credential_format_ok") == "true", "production_credential_format_ok"),
    (receipt_values.get("credential_rotation_attested") == "true", "credential_rotation_attested"),
    (receipt_values.get("official_deepseek_api_preflight_ok") == "true", "official_deepseek_api_preflight_ok"),
    (receipt_values.get("official_modal_preflight_ok") == "true", "official_modal_preflight_ok"),
    (receipt_values.get("official_scorer_preflight_ok") == "true", "official_scorer_preflight_ok"),
    (receipt_values.get("runner_policy_ok") == "true", "runner_policy_ok"),
])
ready_blockers_schema_ok = receipt_values.get("ready_blockers") == expected_ready_blockers
production_ready_blockers_schema_ok = receipt_values.get("production_ready_blockers") == expected_production_ready_blockers
schema_ok = schema_ok and ready_blockers_schema_ok
schema_ok = schema_ok and production_ready_blockers_schema_ok
if not ready_blockers_schema_ok and "ready_blockers" not in schema_issue_paths:
    schema_issue_paths.append("ready_blockers")
if not production_ready_blockers_schema_ok and "production_ready_blockers" not in schema_issue_paths:
    schema_issue_paths.append("production_ready_blockers")
mismatch_paths = [
    key for key in required
    if key in receipt and receipt_values.get(key, "") != current.get(key, "")
]
matches_current = schema_ok and not mismatch_paths
receipt_ok = schema_ok and receipt_ready and current_ready and matches_current
if receipt_parse_issue:
    schema_ok = False
    missing = []
    schema_issue_paths = [receipt_parse_issue]
    receipt_values["ready_blockers"] = receipt_parse_issue
    receipt_values["production_ready_blockers"] = "preflight_receipt_ok"
    receipt_ok = False

print("metric=pro_elevation_preflight_verification")
print("metric_claim=false")
print(f"preflight_receipt_path={receipt_path}")
print(f"selection_manifest_path={receipt_values.get('selection_manifest_path', '')}")
print(f"selection_manifest_sha256={receipt_values.get('selection_manifest_sha256', '')}")
print(f"selection_receipt_ok={receipt_values.get('selection_receipt_ok', 'false')}")
print(f"anti_cherry_pick={receipt_values.get('anti_cherry_pick', 'false')}")
print(f"metric_scope={receipt_values.get('metric_scope', '')}")
print(f"within_task_efficiency_metric_admissible={receipt_values.get('within_task_efficiency_metric_admissible', '')}")
print("preflight_receipt_exists=true")
print(f"preflight_receipt_schema_ok={'true' if schema_ok else 'false'}")
print(f"preflight_receipt_missing_fields={','.join(missing)}")
print(f"preflight_receipt_schema_issue_paths={','.join(schema_issue_paths)}")
print(f"preflight_receipt_mismatch_paths={','.join(mismatch_paths)}")
print(f"receipt_ready_to_run={'true' if receipt_ready else 'false'}")
print(f"current_ready_to_run={'true' if current_ready else 'false'}")
print(f"receipt_production_ready_to_run={'true' if receipt_production_ready else 'false'}")
print(f"current_production_ready_to_run={'true' if current_production_ready else 'false'}")
print(f"ready_blockers={receipt_values.get('ready_blockers', '')}")
print(f"production_ready_blockers={receipt_values.get('production_ready_blockers', '')}")
print(f"receipt_matches_current={'true' if matches_current else 'false'}")
print(f"preflight_receipt_ok={'true' if receipt_ok else 'false'}")
print("no_model_run=true")
print("no_scorer_run=true")
raise SystemExit(0 if receipt_ok else 2)
PYPREVERIFY
}

verify_production_ready_receipt() {
  local receipt_json="${1:-}"
  local verification verify_status
  local receipt_exists schema_ok receipt_ready current_ready receipt_production_ready receipt_production_ready_verified current_production_ready matches_current preflight_ok production_ready_ok production_ready_receipt_blockers
  local selection_manifest_path selection_manifest_sha256 selection_receipt_ok anti_cherry_pick ready_blockers production_ready_blockers mismatch_paths
  local missing_fields schema_issue_paths preflight_receipt_blocker

  verify_status=0
  verification="$(verify_preflight_receipt "$receipt_json")" || verify_status=$?
  receipt_exists="$(report_field "$verification" preflight_receipt_exists false)"
  schema_ok="$(report_field "$verification" preflight_receipt_schema_ok false)"
  missing_fields="$(report_field "$verification" preflight_receipt_missing_fields '')"
  schema_issue_paths="$(report_field "$verification" preflight_receipt_schema_issue_paths '')"
  receipt_ready="$(report_field "$verification" receipt_ready_to_run false)"
  current_ready="$(report_field "$verification" current_ready_to_run false)"
  receipt_production_ready="$(report_field "$verification" receipt_production_ready_to_run false)"
  current_production_ready="$(report_field "$verification" current_production_ready_to_run false)"
  matches_current="$(report_field "$verification" receipt_matches_current false)"
  preflight_ok="$(report_field "$verification" preflight_receipt_ok false)"
  selection_manifest_path="$(report_field "$verification" selection_manifest_path '')"
  selection_manifest_sha256="$(report_field "$verification" selection_manifest_sha256 '')"
  selection_receipt_ok="$(report_field "$verification" selection_receipt_ok false)"
  anti_cherry_pick="$(report_field "$verification" anti_cherry_pick false)"
  ready_blockers="$(report_field "$verification" ready_blockers '')"
  production_ready_blockers="$(report_field "$verification" production_ready_blockers '')"
  mismatch_paths="$(report_field "$verification" preflight_receipt_mismatch_paths '')"
  production_ready_receipt_blockers=""
  receipt_production_ready_verified=false
  if [[ "$receipt_production_ready" == "true" && "$preflight_ok" == "true" ]]; then
    receipt_production_ready_verified=true
  fi
  add_production_ready_receipt_blocker() {
    if [[ "$1" != "true" ]]; then
      if [[ -n "$production_ready_receipt_blockers" ]]; then
        production_ready_receipt_blockers+=","
      fi
      production_ready_receipt_blockers+="$2"
    fi
  }
  preflight_receipt_blocker=preflight_receipt_ok
  if [[ "$receipt_exists" == "true" && -n "$schema_issue_paths" ]]; then
    preflight_receipt_blocker="$schema_issue_paths"
  fi
  add_production_ready_receipt_blocker "$preflight_ok" "$preflight_receipt_blocker"
  add_production_ready_receipt_blocker "$receipt_production_ready_verified" receipt_production_ready_to_run
  add_production_ready_receipt_blocker "$current_production_ready" current_production_ready_to_run
  add_production_ready_receipt_blocker "$matches_current" receipt_matches_current
  production_ready_ok=false
  if [[ -z "$production_ready_receipt_blockers" ]]; then
    production_ready_ok=true
  fi

  cat <<EOF
metric=pro_elevation_production_ready_verification
metric_claim=false
preflight_receipt_path=$receipt_json
selection_manifest_path=$selection_manifest_path
selection_manifest_sha256=$selection_manifest_sha256
selection_receipt_ok=$selection_receipt_ok
anti_cherry_pick=$anti_cherry_pick
preflight_receipt_exists=$receipt_exists
preflight_receipt_schema_ok=$schema_ok
preflight_receipt_missing_fields=$missing_fields
preflight_receipt_schema_issue_paths=$schema_issue_paths
receipt_ready_to_run=$receipt_ready
current_ready_to_run=$current_ready
receipt_production_ready_to_run=$receipt_production_ready
current_production_ready_to_run=$current_production_ready
ready_blockers=$ready_blockers
production_ready_blockers=$production_ready_blockers
preflight_receipt_mismatch_paths=$mismatch_paths
receipt_matches_current=$matches_current
preflight_receipt_ok=$preflight_ok
production_ready_receipt_ok=$production_ready_ok
production_ready_receipt_blockers=$production_ready_receipt_blockers
no_model_run=true
no_scorer_run=true
EOF
  [[ "$production_ready_ok" == "true" ]]
}

frontier_summary_from_log() {
  local log_path="$1"
  local fallback_path="$2"
  local summary_path
  summary_path="$(awk '{for (i = 1; i <= NF; i++) if ($i ~ /^summary=/) {sub(/^summary=/, "", $i); print $i}}' "$log_path" | tail -1)"
  if [[ -z "$summary_path" ]]; then
    summary_path="$fallback_path"
  fi
  case "$summary_path" in
    /*) printf '%s\n' "$summary_path" ;;
    *) printf '%s/%s\n' "$HERE" "$summary_path" ;;
  esac
}

validate_frontier_baseline_summary() {
  local summary_path="$1"
  local baseline_path="$2"
  local baseline_sha="$3"
  local task_provenance_sha="$4"
  shift 4
  "$SWE_PYTHON" - "$summary_path" "$BENCHMARK_SUITE" "$DATASET_NAME" "$baseline_path" "$baseline_sha" "$task_provenance_sha" "$(sha256_text "$@")" "$@" <<'PYFRONTIERSUMMARY'
import json
import sys

path, benchmark_suite, dataset_name, baseline_path, baseline_sha, task_provenance_sha, task_hash, *tasks = sys.argv[1:]
try:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
except Exception as exc:
    print(f"frontier_summary_json_error={type(exc).__name__}:{exc}", file=sys.stderr)
    raise SystemExit(2)

ok = (
    isinstance(data, dict)
    and data.get("metric") == "frontier_baseline_receipt"
    and data.get("metric_claim") is False
    and data.get("benchmark_suite") == benchmark_suite
    and data.get("benchmark_dataset_name") == dataset_name
    and data.get("benchmark_label") == "SWE-bench-Pro"
    and data.get("official_benchmark") is True
    and data.get("baseline_role") == "frontier"
    and data.get("frozen") is True
    and data.get("official_docker") is True
    and isinstance(data.get("frontier_model"), str)
    and bool(data.get("frontier_model"))
    and data.get("task_ids") == tasks
    and data.get("task_ids_sha256") == task_hash
    and data.get("task_provenance_ok") is True
    and data.get("task_provenance_sha256") == task_provenance_sha
    and data.get("suite_preflight_ok") is True
    and data.get("frontier_baseline_path") == baseline_path
    and data.get("frontier_baseline_sha256") == baseline_sha
    and data.get("frontier_baseline_evidence_receipt_ok") is True
    and data.get("sample_failures") == 0
    and data.get("score_failures") == 0
)
if not ok:
    print("frontier_summary_contract=false", file=sys.stderr)
    raise SystemExit(2)
PYFRONTIERSUMMARY
}

frontier_summary_report() {
  local summary_path="$1"
  "$SWE_PYTHON" - "$summary_path" <<'PYFRONTIERREPORT'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
print(f"frontier_model={data['frontier_model']}")
print(f"frontier_baseline_role={data['baseline_role']}")
print(f"frontier_baseline_frozen={'true' if data['frozen'] is True else 'false'}")
print(f"frontier_baseline_official_docker={'true' if data['official_docker'] is True else 'false'}")
print(f"frontier_baseline_benchmark_label={data['benchmark_label']}")
PYFRONTIERREPORT
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
  local baseline_path="$2"
  local baseline_sha="$3"
  local task_ids_sha="$4"
  local selection_manifest_path="$5"
  local selection_manifest_sha="$6"
  shift 6
  "$SWE_PYTHON" - "$summary_path" "$BENCHMARK_SUITE" "$DATASET_NAME" "$baseline_path" "$baseline_sha" "$task_ids_sha" "$selection_manifest_path" "$selection_manifest_sha" "$STUDENT_MODEL" "$@" <<'PYSUMMARYCHECK'
import json
import sys

path, benchmark_suite, dataset_name, baseline_path, baseline_sha, task_ids_sha, selection_manifest_path, selection_manifest_sha, expected_student_model, *tasks = sys.argv[1:]
try:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
except Exception as exc:
    print(f"summary_json_error={type(exc).__name__}:{exc}", file=sys.stderr)
    raise SystemExit(2)

summary_tasks = data.get("task_ids")
task_count = len(tasks)
required_true_fields = (
    "elevation_valid",
    "task_provenance_ok",
    "suite_preflight_ok",
    "frontier_baseline_evidence_receipt_ok",
    "frontier_baseline_provenance_ok",
    "teacher_atomic",
    "anti_replay",
    "selection_receipt_ok",
    "anti_cherry_pick",
    "distinct_tasks",
)
def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)

def close(left, right):
    return number(left) and abs(float(left) - float(right)) <= 1e-12

frontier_resolved = data.get("frontier_baseline_resolved")
student_resolved = data.get("atomic_substrate_resolved")
control_resolved = data.get("deepseek_control_resolved")
frontier_rate = None if task_count == 0 else frontier_resolved / task_count if isinstance(frontier_resolved, int) and not isinstance(frontier_resolved, bool) else None
student_rate = None if task_count == 0 else student_resolved / task_count if isinstance(student_resolved, int) and not isinstance(student_resolved, bool) else None
control_rate = None if task_count == 0 else control_resolved / task_count if isinstance(control_resolved, int) and not isinstance(control_resolved, bool) else None
rate_fields_ok = (
    isinstance(data.get("task_count"), int)
    and data.get("task_count") == task_count
    and isinstance(frontier_resolved, int)
    and isinstance(student_resolved, int)
    and isinstance(control_resolved, int)
    and not any(isinstance(value, bool) for value in (frontier_resolved, student_resolved, control_resolved))
    and 0 <= frontier_resolved <= task_count
    and 0 <= student_resolved <= task_count
    and 0 <= control_resolved <= task_count
    and close(data.get("frontier_solve_rate"), frontier_rate)
    and close(data.get("student_solve_rate"), student_rate)
    and close(data.get("deepseek_control_solve_rate"), control_rate)
    and data.get("elevation_vs_frontier") == student_resolved - frontier_resolved
    and data.get("elevation_vs_deepseek_control") == student_resolved - control_resolved
    and close(data.get("elevation_vs_frontier_solve_rate"), student_rate - frontier_rate)
    and close(data.get("elevation_vs_deepseek_control_solve_rate"), student_rate - control_rate)
)
accumulation_fields_ok = (
    isinstance(data.get("accumulation_index"), int)
    and not isinstance(data.get("accumulation_index"), bool)
    and data.get("accumulation_index") >= 0
    and isinstance(data.get("substrate_weight_count"), int)
    and not isinstance(data.get("substrate_weight_count"), bool)
    and data.get("substrate_weight_count") >= 0
)
ok = (
    isinstance(data, dict)
    and data.get("metric") == "elevation"
    and data.get("metric_claim") is False
    and data.get("benchmark_suite") == benchmark_suite
    and data.get("benchmark_dataset_name") == dataset_name
    and data.get("official_benchmark") is True
    and data.get("metric_scope") == "paired_frontier_solve_rate_delta"
    and data.get("within_task_efficiency_metric_admissible") is False
    and data.get("student_model") == expected_student_model
    and isinstance(summary_tasks, list)
    and summary_tasks == tasks
    and data.get("selected_task_ids_sha256") == task_ids_sha
    and data.get("selection_manifest_path") == selection_manifest_path
    and data.get("selection_manifest_sha256") == selection_manifest_sha
    and data.get("frontier_baseline_path") == baseline_path
    and data.get("frontier_baseline_sha256") == baseline_sha
    and data.get("frontier_baseline_role") == "frontier"
    and data.get("frontier_baseline_frozen") is True
    and data.get("frontier_baseline_official_docker") is True
    and data.get("frontier_baseline_benchmark_label") == "SWE-bench-Pro"
    and data.get("sample_timeouts") == 0
    and data.get("score_failures") == 0
    and data.get("reused_samples") == 0
    and data.get("rerun_timeout_samples") == 0
    and rate_fields_ok
    and accumulation_fields_ok
    and all(data.get(field) is True for field in required_true_fields)
)
if not ok:
    print("summary_json_contract=false", file=sys.stderr)
    raise SystemExit(2)
PYSUMMARYCHECK
}

elevation_metric_report() {
  local summary_path="$1"
  "$SWE_PYTHON" - "$summary_path" <<'PYELEVATIONMETRICS'
import json
import sys

keys = [
    "metric_scope",
    "within_task_efficiency_metric_admissible",
    "frontier_baseline_resolved",
    "frontier_solve_rate",
    "deepseek_control_resolved",
    "deepseek_control_solve_rate",
    "atomic_substrate_resolved",
    "student_solve_rate",
    "elevation_vs_frontier",
    "elevation_vs_frontier_solve_rate",
    "elevation_vs_deepseek_control",
    "elevation_vs_deepseek_control_solve_rate",
    "accumulation_index",
    "substrate_weight_count",
]
with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
for key in keys:
    value = data[key]
    if isinstance(value, bool):
        value = "true" if value else "false"
    print(f"{key}={value}")
PYELEVATIONMETRICS
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
round_receipt_missing_fields=
round_receipt_schema_issue_paths=round_receipt_exists
round_receipt_artifact_hashes_ok=false
round_receipt_task_ids_ok=false
round_receipt_ok=false
production_ready_to_run=false
production_toolchain_ok=false
metric_admissible=false
no_model_run=true
no_scorer_run=true
EOF
    return 2
  fi

  "$SWE_PYTHON" - "$receipt_json" <<'PYROUNDVERIFY'
import hashlib
import json
import subprocess
import sys
from pathlib import Path

receipt_path = Path(sys.argv[1])
required = [
    "metric",
    "metric_claim",
    "production_ready_to_run",
    "metric_admissible",
    "production_toolchain_ok",
    "run_id",
    "benchmark_suite",
    "benchmark_dataset_name",
    "official_benchmark",
    "manifest_path",
    "selected_task_count",
    "selected_task_ids_sha256",
    "selection_manifest_path",
    "selection_manifest_sha256",
    "selection_receipt_ok",
    "anti_cherry_pick",
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
    "frontier_model",
    "frontier_baseline_role",
    "frontier_baseline_frozen",
    "frontier_baseline_official_docker",
    "frontier_baseline_benchmark_label",
    "frontier_baseline_summary_path",
    "frontier_baseline_summary_sha256",
    "frontier_summary_verification_ok",
    "frontier_baseline_evidence_receipt_ok",
    "frontier_baseline_resolved",
    "frontier_solve_rate",
    "deepseek_control_resolved",
    "deepseek_control_solve_rate",
    "atomic_substrate_resolved",
    "student_solve_rate",
    "student_model",
    "elevation_vs_frontier",
    "elevation_vs_frontier_solve_rate",
    "elevation_vs_deepseek_control",
    "elevation_vs_deepseek_control_solve_rate",
    "accumulation_index",
    "substrate_weight_count",
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


def parse_kv(text):
    parsed = {}
    for line in text.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            parsed[key] = value
    return parsed

metric_fields = [
    "metric_scope",
    "within_task_efficiency_metric_admissible",
    "frontier_baseline_resolved",
    "frontier_solve_rate",
    "deepseek_control_resolved",
    "deepseek_control_solve_rate",
    "atomic_substrate_resolved",
    "student_solve_rate",
    "elevation_vs_frontier",
    "elevation_vs_frontier_solve_rate",
    "elevation_vs_deepseek_control",
    "elevation_vs_deepseek_control_solve_rate",
    "accumulation_index",
    "substrate_weight_count",
]

receipt_parse_issue = ""
try:
    with receipt_path.open(encoding="utf-8") as handle:
        receipt = json.load(handle)
except Exception:
    receipt = {}
    receipt_parse_issue = "round_receipt_json"
if not isinstance(receipt, dict):
    receipt = {}
    receipt_parse_issue = "round_receipt_object"

missing = [] if receipt_parse_issue else [key for key in required if key not in receipt]
schema_ok = isinstance(receipt, dict) and not missing
schema_ok = schema_ok and receipt.get("metric") == "pro_elevation_round"
schema_ok = schema_ok and receipt.get("metric_claim") is False
schema_ok = schema_ok and receipt.get("benchmark_suite") == "swe_bench_pro"
schema_ok = schema_ok and receipt.get("benchmark_dataset_name") == "ScaleAI/SWE-bench_Pro"
schema_ok = schema_ok and receipt.get("official_benchmark") is True
schema_ok = schema_ok and receipt.get("metric_scope") == "paired_frontier_solve_rate_delta"
schema_ok = schema_ok and receipt.get("within_task_efficiency_metric_admissible") is False
schema_ok = schema_ok and receipt.get("selection_manifest_path") == receipt.get("manifest_path")
schema_ok = schema_ok and isinstance(receipt.get("selection_manifest_sha256"), str) and len(receipt.get("selection_manifest_sha256")) == 64
schema_ok = schema_ok and receipt.get("selection_receipt_ok") is True
schema_ok = schema_ok and receipt.get("anti_cherry_pick") is True
schema_ok = schema_ok and receipt.get("preflight_verification_ok") is True
schema_ok = schema_ok and receipt.get("task_provenance_ok") is True
schema_ok = schema_ok and receipt.get("frontier_baseline_evidence_receipt_ok") is True
schema_ok = schema_ok and receipt.get("elevation_valid_if_run") is True
schema_ok = schema_ok and isinstance(receipt.get("production_ready_to_run"), bool)
schema_ok = schema_ok and ("ready_blockers" not in receipt or isinstance(receipt.get("ready_blockers"), str))
schema_ok = schema_ok and ("production_ready_blockers" not in receipt or isinstance(receipt.get("production_ready_blockers"), str))
schema_ok = schema_ok and isinstance(receipt.get("production_toolchain_ok"), bool)
schema_ok = schema_ok and isinstance(receipt.get("metric_admissible"), bool)
schema_ok = schema_ok and isinstance(receipt.get("frontier_model"), str) and bool(receipt.get("frontier_model"))
schema_ok = schema_ok and receipt.get("frontier_baseline_role") == "frontier"
schema_ok = schema_ok and receipt.get("frontier_baseline_frozen") is True
schema_ok = schema_ok and receipt.get("frontier_baseline_official_docker") is True
schema_ok = schema_ok and receipt.get("frontier_baseline_benchmark_label") == "SWE-bench-Pro"
schema_ok = schema_ok and receipt.get("frontier_summary_verification_ok") is True
schema_ok = schema_ok and receipt.get("student_model") == "deepseek-v4-pro"
schema_ok = schema_ok and isinstance(receipt.get("accumulation_index"), int) and not isinstance(receipt.get("accumulation_index"), bool) and receipt.get("accumulation_index") >= 0
schema_ok = schema_ok and isinstance(receipt.get("substrate_weight_count"), int) and not isinstance(receipt.get("substrate_weight_count"), bool) and receipt.get("substrate_weight_count") >= 0
try:
    embedded_round_receipt_path = Path(str(receipt.get("round_receipt_path"))).resolve()
    round_receipt_path_ok = embedded_round_receipt_path == receipt_path.resolve()
except Exception:
    round_receipt_path_ok = False
schema_ok = schema_ok and round_receipt_path_ok
schema_issue_paths = []

def add_schema_issue(ok, path):
    if not ok and path not in schema_issue_paths:
        schema_issue_paths.append(path)

if isinstance(receipt, dict):
    for key in missing:
        add_schema_issue(False, key)
    add_schema_issue(receipt.get("benchmark_suite") == "swe_bench_pro", "benchmark_suite")
    add_schema_issue(receipt.get("benchmark_dataset_name") == "ScaleAI/SWE-bench_Pro", "benchmark_dataset_name")
    add_schema_issue(receipt.get("official_benchmark") is True, "official_benchmark")
    add_schema_issue(receipt.get("frontier_baseline_role") == "frontier", "frontier_baseline_role")
    add_schema_issue(receipt.get("frontier_baseline_frozen") is True, "frontier_baseline_frozen")
    add_schema_issue(receipt.get("frontier_baseline_official_docker") is True, "frontier_baseline_official_docker")
    add_schema_issue(receipt.get("frontier_baseline_benchmark_label") == "SWE-bench-Pro", "frontier_baseline_benchmark_label")
    add_schema_issue(receipt.get("student_model") == "deepseek-v4-pro", "student_model")
else:
    schema_issue_paths = list(required)
provenance_sha = receipt.get("task_provenance_sha256")
provenance_sha_ok = isinstance(provenance_sha, str) and len(provenance_sha) == 64 and all(char in "0123456789abcdef" for char in provenance_sha)
preflight_provenance_ok = False
production_toolchain_ok = False
preflight_path_value = receipt.get("preflight_receipt_path")
if isinstance(preflight_path_value, str):
    preflight_path = Path(preflight_path_value)
    if preflight_path.is_file():
        try:
            with preflight_path.open(encoding="utf-8") as handle:
                preflight = json.load(handle)
            expected_preflight_production_ready = (
                preflight.get("ready_to_run") is True
                and preflight.get("canonical_toolchain") is True
                and preflight.get("test_runner_override_allowed") is False
                and preflight.get("production_credential_format_ok") is True
                and preflight.get("credential_rotation_attested") is True
                and preflight.get("official_deepseek_api_preflight_ok") is True
                and preflight.get("official_modal_preflight_ok") is True
                and preflight.get("official_scorer_preflight_ok") is True
                and preflight.get("runner_policy_ok") is True
            )
            modal_credentials_format_ok = (
                preflight.get("modal_token_id_format_ok") is True
                and preflight.get("modal_token_secret_format_ok") is True
            )
            production_credential_format_ok = (
                preflight.get("deepseek_api_key_format_ok") is True
                and modal_credentials_format_ok
            )
            expected_credential_format_ok = (
                production_credential_format_ok
                or preflight.get("credential_format_bypassed_by_test_runner") is True
            )
            expected_credential_rotation_attestation_ok = (
                preflight.get("credential_rotation_attested") is True
                or preflight.get("credential_rotation_attestation_bypassed_by_test_runner") is True
            )
            official_deepseek_api_preflight_ok = (
                preflight.get("deepseek_auth_ok") is True
                and preflight.get("deepseek_balance_available") is True
            )
            expected_deepseek_api_preflight_ok = (
                official_deepseek_api_preflight_ok
                or preflight.get("deepseek_api_preflight_bypassed_by_test_runner") is True
            )
            official_modal_preflight_ok = (
                preflight.get("modal_cli_present") is True
                and preflight.get("modal_auth_ok") is True
            )
            expected_modal_preflight_ok = (
                official_modal_preflight_ok
                or preflight.get("modal_preflight_bypassed_by_test_runner") is True
            )
            preflight_production_ready = preflight.get("production_ready_to_run") is True
            preflight_provenance_ok = (
                preflight.get("metric") == "pro_elevation_preflight"
                and preflight.get("metric_claim") is False
                and preflight.get("benchmark_suite") == receipt.get("benchmark_suite")
                and preflight.get("benchmark_dataset_name") == receipt.get("benchmark_dataset_name")
                and preflight.get("official_benchmark") is True
                and preflight.get("manifest_path") == receipt.get("manifest_path")
                and preflight.get("selected_task_count") == receipt.get("selected_task_count")
                and preflight.get("selected_task_ids_sha256") == receipt.get("selected_task_ids_sha256")
                and preflight.get("selection_manifest_path") == receipt.get("selection_manifest_path")
                and preflight.get("selection_manifest_sha256") == receipt.get("selection_manifest_sha256")
                and preflight.get("selection_receipt_ok") is True
                and preflight.get("anti_cherry_pick") is True
                and preflight.get("deepseek_api_key_present") is True
                and preflight.get("modal_token_id_present") is True
                and preflight.get("modal_token_secret_present") is True
                and preflight.get("modal_credentials_present") is True
                and isinstance(preflight.get("deepseek_api_key_format_ok"), bool)
                and isinstance(preflight.get("modal_token_id_format_ok"), bool)
                and isinstance(preflight.get("modal_token_secret_format_ok"), bool)
                and preflight.get("modal_credentials_format_ok") is modal_credentials_format_ok
                and preflight.get("credential_format_bypassed_by_test_runner") is preflight.get("test_runner_override_allowed")
                and preflight.get("credential_format_ok") is expected_credential_format_ok
                and preflight.get("production_credential_format_ok") is production_credential_format_ok
                and isinstance(preflight.get("credential_rotation_attested"), bool)
                and preflight.get("credential_rotation_attestation_bypassed_by_test_runner") is preflight.get("test_runner_override_allowed")
                and preflight.get("credential_rotation_attestation_ok") is expected_credential_rotation_attestation_ok
                and isinstance(preflight.get("deepseek_auth_ok"), bool)
                and isinstance(preflight.get("deepseek_balance_available"), bool)
                and preflight.get("official_deepseek_api_preflight_ok") is official_deepseek_api_preflight_ok
                and preflight.get("deepseek_api_preflight_bypassed_by_test_runner") is preflight.get("test_runner_override_allowed")
                and preflight.get("deepseek_api_preflight_ok") is expected_deepseek_api_preflight_ok
                and isinstance(preflight.get("modal_cli_present"), bool)
                and isinstance(preflight.get("modal_auth_ok"), bool)
                and preflight.get("official_modal_preflight_ok") is official_modal_preflight_ok
                and preflight.get("modal_preflight_bypassed_by_test_runner") is preflight.get("test_runner_override_allowed")
                and preflight.get("modal_preflight_ok") is expected_modal_preflight_ok
                and preflight.get("credential_source") == "env"
                and preflight.get("credential_file_allowed") is False
                and preflight.get("runner_policy_ok") is True
                and preflight.get("scorer_preflight_ok") is True
                and (
                    preflight.get("official_scorer_preflight_ok") is True
                    or preflight.get("scorer_preflight_bypassed_by_test_runner") is True
                )
                and preflight.get("frontier_runner_ok") is True
                and preflight.get("frontier_baseline_runner") == receipt.get("frontier_baseline_runner")
                and preflight.get("frontier_baseline_runner_sha256") == receipt.get("frontier_baseline_runner_sha256")
                and preflight.get("elevation_stream_ok") is True
                and preflight.get("elevation_stream") == receipt.get("elevation_stream")
                and preflight.get("elevation_stream_sha256") == receipt.get("elevation_stream_sha256")
                and preflight.get("weights_ok") is True
                and preflight.get("task_layout_ok") is True
                and preflight.get("task_provenance_ok") is True
                and preflight.get("task_provenance_sha256") == provenance_sha
                and preflight.get("suite_pristine_layout_ok") is True
                and preflight.get("ready_to_run") is True
                and preflight.get("production_ready_to_run") is expected_preflight_production_ready
                and (
                    "ready_blockers" not in receipt
                    or preflight.get("ready_blockers") == receipt.get("ready_blockers")
                )
                and (
                    "production_ready_blockers" not in receipt
                    or preflight.get("production_ready_blockers") == receipt.get("production_ready_blockers")
                )
                and preflight.get("no_model_run") is True
                and preflight.get("no_scorer_run") is True
            )
            production_toolchain_ok = preflight_production_ready
        except Exception:
            preflight_provenance_ok = False
add_schema_issue(receipt.get("production_ready_to_run") == production_toolchain_ok, "production_ready_to_run")
add_schema_issue(receipt.get("production_toolchain_ok") == production_toolchain_ok, "production_toolchain_ok")
add_schema_issue(receipt.get("metric_admissible") == production_toolchain_ok, "metric_admissible")
frontier_summary_ok = False
frontier_summary_verification_ok = False
frontier_summary_path_value = receipt.get("frontier_baseline_summary_path")
if isinstance(frontier_summary_path_value, str):
    frontier_summary_path = Path(frontier_summary_path_value)
    if frontier_summary_path.is_file():
        try:
            with frontier_summary_path.open(encoding="utf-8") as handle:
                frontier_summary = json.load(handle)
            frontier_summary_ok = (
                frontier_summary.get("metric") == "frontier_baseline_receipt"
                and frontier_summary.get("metric_claim") is False
                and frontier_summary.get("benchmark_suite") == receipt.get("benchmark_suite")
                and frontier_summary.get("benchmark_dataset_name") == receipt.get("benchmark_dataset_name")
                and frontier_summary.get("benchmark_label") == receipt.get("frontier_baseline_benchmark_label")
                and frontier_summary.get("official_benchmark") is True
                and frontier_summary.get("baseline_role") == receipt.get("frontier_baseline_role")
                and frontier_summary.get("frozen") is receipt.get("frontier_baseline_frozen")
                and frontier_summary.get("official_docker") is receipt.get("frontier_baseline_official_docker")
                and frontier_summary.get("frontier_model") == receipt.get("frontier_model")
                and frontier_summary.get("task_ids") == receipt.get("task_ids")
                and frontier_summary.get("task_ids_sha256") == receipt.get("selected_task_ids_sha256")
                and frontier_summary.get("task_provenance_ok") is True
                and frontier_summary.get("task_provenance_sha256") == provenance_sha
                and frontier_summary.get("suite_preflight_ok") is True
                and frontier_summary.get("frontier_baseline_path") == receipt.get("frontier_baseline_path")
                and frontier_summary.get("frontier_baseline_sha256") == receipt.get("frontier_baseline_sha256")
                and frontier_summary.get("frontier_baseline_evidence_receipt_ok") is True
                and frontier_summary.get("sample_failures") == 0
                and frontier_summary.get("score_failures") == 0
            )
            add_schema_issue(frontier_summary.get("metric") == "frontier_baseline_receipt", "frontier_summary.metric")
            add_schema_issue(frontier_summary.get("metric_claim") is False, "frontier_summary.metric_claim")
            if receipt.get("benchmark_suite") == "swe_bench_pro":
                add_schema_issue(frontier_summary.get("benchmark_suite") == receipt.get("benchmark_suite"), "frontier_summary.benchmark_suite")
            if receipt.get("benchmark_dataset_name") == "ScaleAI/SWE-bench_Pro":
                add_schema_issue(frontier_summary.get("benchmark_dataset_name") == receipt.get("benchmark_dataset_name"), "frontier_summary.benchmark_dataset_name")
            if receipt.get("frontier_baseline_benchmark_label") == "SWE-bench-Pro":
                add_schema_issue(frontier_summary.get("benchmark_label") == receipt.get("frontier_baseline_benchmark_label"), "frontier_summary.benchmark_label")
            if receipt.get("official_benchmark") is True:
                add_schema_issue(frontier_summary.get("official_benchmark") is True, "frontier_summary.official_benchmark")
            if receipt.get("frontier_baseline_role") == "frontier":
                add_schema_issue(frontier_summary.get("baseline_role") == receipt.get("frontier_baseline_role"), "frontier_summary.baseline_role")
            if receipt.get("frontier_baseline_frozen") is True:
                add_schema_issue(frontier_summary.get("frozen") is receipt.get("frontier_baseline_frozen"), "frontier_summary.frozen")
            if receipt.get("frontier_baseline_official_docker") is True:
                add_schema_issue(frontier_summary.get("official_docker") is receipt.get("frontier_baseline_official_docker"), "frontier_summary.official_docker")
            add_schema_issue(frontier_summary.get("frontier_model") == receipt.get("frontier_model"), "frontier_model")
            add_schema_issue(frontier_summary.get("task_provenance_ok") is True, "frontier_summary.task_provenance_ok")
            if provenance_sha_ok:
                add_schema_issue(frontier_summary.get("task_provenance_sha256") == provenance_sha, "frontier_summary.task_provenance_sha256")
            add_schema_issue(frontier_summary.get("suite_preflight_ok") is True, "frontier_summary.suite_preflight_ok")
            add_schema_issue(frontier_summary.get("frontier_baseline_evidence_receipt_ok") is True, "frontier_summary.frontier_baseline_evidence_receipt_ok")
            add_schema_issue(frontier_summary.get("sample_failures") == 0, "frontier_summary.sample_failures")
            add_schema_issue(frontier_summary.get("score_failures") == 0, "frontier_summary.score_failures")
        except Exception:
            frontier_summary_ok = False
frontier_runner_value = receipt.get("frontier_baseline_runner")
if isinstance(frontier_runner_value, str) and isinstance(frontier_summary_path_value, str):
    frontier_runner = Path(frontier_runner_value)
    if frontier_runner.is_file():
        try:
            completed = subprocess.run(
                [str(frontier_runner), "--verify-summary", frontier_summary_path_value],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
                timeout=60,
            )
            verification = parse_kv(completed.stdout)
            frontier_summary_verification_ok = (
                completed.returncode == 0
                and verification.get("frontier_summary_ok") == "true"
                and verification.get("no_model_run") == "true"
                and verification.get("no_scorer_run") == "true"
            )
        except Exception:
            frontier_summary_verification_ok = False
elevation_summary_ok = False
elevation_summary_path_value = receipt.get("elevation_summary_path")
if isinstance(elevation_summary_path_value, str):
    elevation_summary_path = Path(elevation_summary_path_value)
    if elevation_summary_path.is_file():
        try:
            with elevation_summary_path.open(encoding="utf-8") as handle:
                elevation_summary = json.load(handle)
            elevation_summary_ok = (
                elevation_summary.get("metric") == "elevation"
                and elevation_summary.get("metric_claim") is False
                and elevation_summary.get("benchmark_suite") == receipt.get("benchmark_suite")
                and elevation_summary.get("benchmark_dataset_name") == receipt.get("benchmark_dataset_name")
                and elevation_summary.get("official_benchmark") is True
                and elevation_summary.get("metric_scope") == receipt.get("metric_scope")
                and elevation_summary.get("within_task_efficiency_metric_admissible") is receipt.get("within_task_efficiency_metric_admissible")
                and elevation_summary.get("student_model") == "deepseek-v4-pro"
                and receipt.get("student_model") == elevation_summary.get("student_model")
                and elevation_summary.get("task_ids") == receipt.get("task_ids")
                and elevation_summary.get("selected_task_ids_sha256") == receipt.get("selected_task_ids_sha256")
                and elevation_summary.get("frontier_baseline_path") == receipt.get("frontier_baseline_path")
                and elevation_summary.get("frontier_baseline_sha256") == receipt.get("frontier_baseline_sha256")
                and elevation_summary.get("frontier_baseline_role") == receipt.get("frontier_baseline_role")
                and elevation_summary.get("frontier_baseline_frozen") is receipt.get("frontier_baseline_frozen")
                and elevation_summary.get("frontier_baseline_official_docker") is receipt.get("frontier_baseline_official_docker")
                and elevation_summary.get("frontier_baseline_benchmark_label") == receipt.get("frontier_baseline_benchmark_label")
                and elevation_summary.get("elevation_valid") is True
                and elevation_summary.get("sample_timeouts") == 0
                and elevation_summary.get("score_failures") == 0
                and elevation_summary.get("reused_samples") == 0
                and elevation_summary.get("rerun_timeout_samples") == 0
                and elevation_summary.get("task_provenance_ok") is True
                and elevation_summary.get("suite_preflight_ok") is True
                and elevation_summary.get("frontier_baseline_evidence_receipt_ok") is True
                and elevation_summary.get("frontier_baseline_provenance_ok") is True
                and elevation_summary.get("teacher_atomic") is True
                and elevation_summary.get("anti_replay") is True
                and elevation_summary.get("selection_receipt_ok") is True
                and elevation_summary.get("anti_cherry_pick") is True
                and elevation_summary.get("selection_manifest_path") == receipt.get("selection_manifest_path")
                and elevation_summary.get("selection_manifest_sha256") == receipt.get("selection_manifest_sha256")
                and elevation_summary.get("distinct_tasks") is True
            )
            add_schema_issue(elevation_summary.get("metric") == "elevation", "elevation_summary.metric")
            add_schema_issue(elevation_summary.get("metric_claim") is False, "elevation_summary.metric_claim")
            if receipt.get("benchmark_suite") == "swe_bench_pro":
                add_schema_issue(elevation_summary.get("benchmark_suite") == receipt.get("benchmark_suite"), "elevation_summary.benchmark_suite")
            if receipt.get("benchmark_dataset_name") == "ScaleAI/SWE-bench_Pro":
                add_schema_issue(elevation_summary.get("benchmark_dataset_name") == receipt.get("benchmark_dataset_name"), "elevation_summary.benchmark_dataset_name")
            if receipt.get("official_benchmark") is True:
                add_schema_issue(elevation_summary.get("official_benchmark") is True, "elevation_summary.official_benchmark")
            if receipt.get("metric_scope") == "paired_frontier_solve_rate_delta":
                add_schema_issue(elevation_summary.get("metric_scope") == receipt.get("metric_scope"), "elevation_summary.metric_scope")
            if receipt.get("within_task_efficiency_metric_admissible") is False:
                add_schema_issue(elevation_summary.get("within_task_efficiency_metric_admissible") is receipt.get("within_task_efficiency_metric_admissible"), "elevation_summary.within_task_efficiency_metric_admissible")
            if receipt.get("student_model") == "deepseek-v4-pro":
                add_schema_issue(elevation_summary.get("student_model") == receipt.get("student_model"), "elevation_summary.student_model")
            add_schema_issue(elevation_summary.get("task_ids") == receipt.get("task_ids"), "elevation_summary.task_ids")
            add_schema_issue(elevation_summary.get("selected_task_ids_sha256") == receipt.get("selected_task_ids_sha256"), "elevation_summary.selected_task_ids_sha256")
            add_schema_issue(elevation_summary.get("frontier_baseline_path") == receipt.get("frontier_baseline_path"), "elevation_summary.frontier_baseline_path")
            add_schema_issue(elevation_summary.get("frontier_baseline_sha256") == receipt.get("frontier_baseline_sha256"), "elevation_summary.frontier_baseline_sha256")
            if receipt.get("frontier_baseline_role") == "frontier":
                add_schema_issue(elevation_summary.get("frontier_baseline_role") == receipt.get("frontier_baseline_role"), "elevation_summary.frontier_baseline_role")
            if receipt.get("frontier_baseline_frozen") is True:
                add_schema_issue(elevation_summary.get("frontier_baseline_frozen") is receipt.get("frontier_baseline_frozen"), "elevation_summary.frontier_baseline_frozen")
            if receipt.get("frontier_baseline_official_docker") is True:
                add_schema_issue(elevation_summary.get("frontier_baseline_official_docker") is receipt.get("frontier_baseline_official_docker"), "elevation_summary.frontier_baseline_official_docker")
            if receipt.get("frontier_baseline_benchmark_label") == "SWE-bench-Pro":
                add_schema_issue(elevation_summary.get("frontier_baseline_benchmark_label") == receipt.get("frontier_baseline_benchmark_label"), "elevation_summary.frontier_baseline_benchmark_label")
            add_schema_issue(elevation_summary.get("elevation_valid") is True, "elevation_summary.elevation_valid")
            add_schema_issue(elevation_summary.get("sample_timeouts") == 0, "elevation_summary.sample_timeouts")
            add_schema_issue(elevation_summary.get("score_failures") == 0, "elevation_summary.score_failures")
            add_schema_issue(elevation_summary.get("reused_samples") == 0, "elevation_summary.reused_samples")
            add_schema_issue(elevation_summary.get("rerun_timeout_samples") == 0, "elevation_summary.rerun_timeout_samples")
            add_schema_issue(elevation_summary.get("task_provenance_ok") is True, "elevation_summary.task_provenance_ok")
            add_schema_issue(elevation_summary.get("suite_preflight_ok") is True, "elevation_summary.suite_preflight_ok")
            add_schema_issue(elevation_summary.get("frontier_baseline_evidence_receipt_ok") is True, "elevation_summary.frontier_baseline_evidence_receipt_ok")
            add_schema_issue(elevation_summary.get("frontier_baseline_provenance_ok") is True, "elevation_summary.frontier_baseline_provenance_ok")
            add_schema_issue(elevation_summary.get("teacher_atomic") is True, "elevation_summary.teacher_atomic")
            add_schema_issue(elevation_summary.get("anti_replay") is True, "elevation_summary.anti_replay")
            add_schema_issue(elevation_summary.get("selection_receipt_ok") is True, "elevation_summary.selection_receipt_ok")
            add_schema_issue(elevation_summary.get("anti_cherry_pick") is True, "elevation_summary.anti_cherry_pick")
            add_schema_issue(elevation_summary.get("selection_manifest_path") == receipt.get("selection_manifest_path"), "elevation_summary.selection_manifest_path")
            add_schema_issue(elevation_summary.get("selection_manifest_sha256") == receipt.get("selection_manifest_sha256"), "elevation_summary.selection_manifest_sha256")
            add_schema_issue(elevation_summary.get("distinct_tasks") is True, "elevation_summary.distinct_tasks")
            manifest_path_value = receipt.get("selection_manifest_path")
            if not isinstance(manifest_path_value, str) or not Path(manifest_path_value).is_file() or receipt.get("selection_manifest_sha256") != sha256_file(Path(manifest_path_value)):
                elevation_summary_ok = False
            tasks = receipt.get("task_ids")
            task_count = len(tasks) if isinstance(tasks, list) else -1
            frontier_resolved = elevation_summary.get("frontier_baseline_resolved")
            student_resolved = elevation_summary.get("atomic_substrate_resolved")
            control_resolved = elevation_summary.get("deepseek_control_resolved")
            def number(value):
                return isinstance(value, (int, float)) and not isinstance(value, bool)
            def close(left, right):
                return number(left) and abs(float(left) - float(right)) <= 1e-12
            add_schema_issue(
                isinstance(elevation_summary.get("task_count"), int)
                and not isinstance(elevation_summary.get("task_count"), bool)
                and elevation_summary.get("task_count") == task_count
                and task_count > 0,
                "elevation_summary.task_count",
            )
            add_schema_issue(
                isinstance(frontier_resolved, int)
                and not isinstance(frontier_resolved, bool)
                and 0 <= frontier_resolved <= task_count,
                "elevation_summary.frontier_baseline_resolved",
            )
            add_schema_issue(
                isinstance(student_resolved, int)
                and not isinstance(student_resolved, bool)
                and 0 <= student_resolved <= task_count,
                "elevation_summary.atomic_substrate_resolved",
            )
            add_schema_issue(
                isinstance(control_resolved, int)
                and not isinstance(control_resolved, bool)
                and 0 <= control_resolved <= task_count,
                "elevation_summary.deepseek_control_resolved",
            )
            if (
                not isinstance(elevation_summary.get("task_count"), int)
                or elevation_summary.get("task_count") != task_count
                or task_count <= 0
                or not isinstance(frontier_resolved, int)
                or not isinstance(student_resolved, int)
                or not isinstance(control_resolved, int)
                or any(isinstance(value, bool) for value in (frontier_resolved, student_resolved, control_resolved))
                or not (0 <= frontier_resolved <= task_count)
                or not (0 <= student_resolved <= task_count)
                or not (0 <= control_resolved <= task_count)
            ):
                elevation_summary_ok = False
            else:
                frontier_rate = frontier_resolved / task_count
                student_rate = student_resolved / task_count
                control_rate = control_resolved / task_count
                formula_expectations = {
                    "frontier_solve_rate": frontier_rate,
                    "student_solve_rate": student_rate,
                    "deepseek_control_solve_rate": control_rate,
                    "elevation_vs_frontier": student_resolved - frontier_resolved,
                    "elevation_vs_deepseek_control": student_resolved - control_resolved,
                    "elevation_vs_frontier_solve_rate": student_rate - frontier_rate,
                    "elevation_vs_deepseek_control_solve_rate": student_rate - control_rate,
                }

                def formula_ok(key):
                    expected = formula_expectations[key]
                    value = elevation_summary.get(key)
                    if isinstance(expected, float):
                        return close(value, expected)
                    return value == expected

                for key in formula_expectations:
                    add_schema_issue(formula_ok(key), f"elevation_summary.{key}")
                elevation_summary_ok = (
                    elevation_summary_ok
                    and all(formula_ok(key) for key in formula_expectations)
                    and all(receipt.get(key) == elevation_summary.get(key) for key in metric_fields)
                )
                for key in metric_fields:
                    if key in formula_expectations:
                        add_schema_issue((not formula_ok(key)) or receipt.get(key) == elevation_summary.get(key), key)
                    else:
                        add_schema_issue(receipt.get(key) == elevation_summary.get(key), key)
        except Exception:
            elevation_summary_ok = False
schema_ok = (
    schema_ok
    and provenance_sha_ok
    and preflight_provenance_ok
    and receipt.get("production_ready_to_run") == production_toolchain_ok
    and receipt.get("production_toolchain_ok") == production_toolchain_ok
    and receipt.get("metric_admissible") == production_toolchain_ok
    and frontier_summary_ok
    and frontier_summary_verification_ok
    and elevation_summary_ok
)

hash_pairs = [
    ("frontier_baseline_runner", "frontier_baseline_runner_sha256"),
    ("elevation_stream", "elevation_stream_sha256"),
    ("weights_path", "weights_sha256"),
    ("preflight_receipt_path", "preflight_receipt_sha256"),
    ("frontier_baseline_path", "frontier_baseline_sha256"),
    ("frontier_baseline_summary_path", "frontier_baseline_summary_sha256"),
    ("elevation_summary_path", "elevation_summary_sha256"),
]
artifact_hashes_ok = schema_ok
artifact_mismatch_paths = []
for path_key, hash_key in hash_pairs:
    path_value = receipt.get(path_key)
    expected_hash = receipt.get(hash_key)
    if not isinstance(path_value, str):
        artifact_hashes_ok = False
        artifact_mismatch_paths.append(path_key)
        continue
    if not isinstance(expected_hash, str):
        artifact_hashes_ok = False
        artifact_mismatch_paths.append(hash_key)
        continue
    path = Path(path_value)
    if not path.is_file():
        artifact_hashes_ok = False
        artifact_mismatch_paths.append(path_key)
        continue
    if sha256_file(path) != expected_hash:
        artifact_hashes_ok = False
        artifact_mismatch_paths.append(hash_key)

tasks = receipt.get("task_ids")
task_mismatch_paths = []
tasks_valid = isinstance(tasks, list) and all(isinstance(task, str) and task for task in tasks)
if not tasks_valid:
    task_mismatch_paths.append("task_ids")
try:
    selected_count = int(receipt.get("selected_task_count"))
except Exception:
    selected_count = -1
if not tasks_valid or selected_count != len(tasks):
    task_mismatch_paths.append("selected_task_count")
selected_task_ids_sha = receipt.get("selected_task_ids_sha256")
if not isinstance(selected_task_ids_sha, str) or not tasks_valid or sha256_text(tasks) != selected_task_ids_sha:
    task_mismatch_paths.append("selected_task_ids_sha256")
task_ids_ok = not task_mismatch_paths
if receipt_parse_issue:
    schema_ok = False
    missing = []
    schema_issue_paths = [receipt_parse_issue]

receipt_sha256 = sha256_file(receipt_path)
receipt_ok = schema_ok and artifact_hashes_ok and task_ids_ok
production_toolchain_ok = bool(production_toolchain_ok)
metric_admissible = receipt_ok and production_toolchain_ok and receipt.get("metric_admissible") is True

print("metric=pro_elevation_round_receipt_verification")
print("metric_claim=false")
print(f"round_receipt_path={receipt_path}")
print(f"selection_manifest_path={receipt.get('selection_manifest_path') if isinstance(receipt, dict) else ''}")
print(f"selection_manifest_sha256={receipt.get('selection_manifest_sha256') if isinstance(receipt, dict) else ''}")
print(f"selection_receipt_ok={'true' if isinstance(receipt, dict) and receipt.get('selection_receipt_ok') is True else 'false'}")
print(f"anti_cherry_pick={'true' if isinstance(receipt, dict) and receipt.get('anti_cherry_pick') is True else 'false'}")
print("round_receipt_exists=true")
print(f"round_receipt_sha256={receipt_sha256}")
print(f"round_receipt_schema_ok={'true' if schema_ok else 'false'}")
print(f"round_receipt_missing_fields={','.join(missing)}")
print(f"round_receipt_schema_issue_paths={','.join(schema_issue_paths)}")
print(f"round_receipt_artifact_hashes_ok={'true' if artifact_hashes_ok else 'false'}")
print(f"round_receipt_artifact_mismatch_paths={','.join(artifact_mismatch_paths)}")
print(f"round_receipt_task_ids_ok={'true' if task_ids_ok else 'false'}")
print(f"round_receipt_task_mismatch_paths={','.join(task_mismatch_paths)}")
print(f"round_receipt_ok={'true' if receipt_ok else 'false'}")
print(f"production_ready_to_run={'true' if production_toolchain_ok else 'false'}")
print(f"production_toolchain_ok={'true' if production_toolchain_ok else 'false'}")
print(f"metric_admissible={'true' if metric_admissible else 'false'}")
print(f"metric_scope={receipt.get('metric_scope') if isinstance(receipt, dict) else ''}")
print(f"within_task_efficiency_metric_admissible={'true' if isinstance(receipt, dict) and receipt.get('within_task_efficiency_metric_admissible') is True else 'false'}")
print(f"frontier_model={receipt.get('frontier_model') if isinstance(receipt, dict) else ''}")
print(f"frontier_baseline_role={receipt.get('frontier_baseline_role') if isinstance(receipt, dict) else ''}")
print(f"frontier_baseline_frozen={'true' if isinstance(receipt, dict) and receipt.get('frontier_baseline_frozen') is True else 'false'}")
print(f"frontier_baseline_official_docker={'true' if isinstance(receipt, dict) and receipt.get('frontier_baseline_official_docker') is True else 'false'}")
print(f"frontier_baseline_benchmark_label={receipt.get('frontier_baseline_benchmark_label') if isinstance(receipt, dict) else ''}")
print(f"frontier_summary_verification_ok={'true' if frontier_summary_verification_ok else 'false'}")
print(f"student_model={receipt.get('student_model') if isinstance(receipt, dict) else ''}")
for key in metric_fields:
    value = receipt.get(key) if isinstance(receipt, dict) else ""
    print(f"{key}={value}")
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

if [[ "${1:-}" == "--production-ready" ]]; then
  shift
  emit_production_ready "${1:-}"
  exit $?
fi

if [[ "${1:-}" == "--verify-preflight" ]]; then
  shift
  verify_preflight_receipt "${1:-}"
  exit $?
fi

if [[ "${1:-}" == "--verify-production-ready" ]]; then
  shift
  verify_production_ready_receipt "${1:-}"
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
selection_manifest_sha256="$(sha256_file "$MANIFEST")"
if [[ "${#TASKS[@]}" -eq 0 ]]; then
  echo "Pro elevation manifest has no selected_task_ids: $MANIFEST" >&2
  exit 2
fi

RUN_ID="${ATOMIC_PRO_ELEVATION_RUN_ID:-pro_elevation_$(sanitize "$RUN_TAG")_T${#TASKS[@]}_$(date -u +%Y%m%dT%H%M%SZ)_$$}"
OUTDIR="$OUTROOT/$RUN_ID"
BASELINE="$OUTDIR/frontier_baseline.json"
PREFLIGHT="$OUTDIR/preflight.json"
ROUND_RECEIPT="$OUTDIR/round_receipt.json"
FRONTIER_LOG="$OUTDIR/frontier_baseline_runner.log"
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
preflight_production_ready_to_run="$(report_field "$preflight_report" production_ready_to_run false)"
preflight_ready_blockers="$(report_field "$preflight_report" ready_blockers '')"
preflight_production_ready_blockers="$(report_field "$preflight_report" production_ready_blockers '')"
preflight_canonical_toolchain="$(report_field "$preflight_report" canonical_toolchain false)"
preflight_test_runner_override_allowed="$(report_field "$preflight_report" test_runner_override_allowed false)"
preflight_runner_policy_ok="$(report_field "$preflight_report" runner_policy_ok false)"
production_toolchain_ok="$preflight_production_ready_to_run"
metric_admissible="$production_toolchain_ok"
preflight_receipt_sha256="$(sha256_file "$PREFLIGHT")"
frontier_runner_sha256="$(sha256_file "$FRONTIER_RUNNER")"
elevation_stream_sha256="$(sha256_file "$ELEVATION_STREAM")"

echo "=== PRO ELEVATION ROUND $RUN_ID ==="
echo "manifest=$MANIFEST"
echo "tasks=${TASKS[*]}"
echo "preflight_receipt_path=$PREFLIGHT"
echo "preflight_verification_ok=$preflight_verification_ok"
echo "task_provenance_sha256=$task_provenance_sha256"
echo "production_ready_to_run=$preflight_production_ready_to_run"
echo "ready_blockers=$preflight_ready_blockers"
echo "production_ready_blockers=$preflight_production_ready_blockers"
echo "production_toolchain_ok=$production_toolchain_ok"
echo "metric_admissible=$metric_admissible"
echo "frontier_baseline_runner=$FRONTIER_RUNNER"
echo "frontier_baseline_runner_sha256=$frontier_runner_sha256"
echo "elevation_stream=$ELEVATION_STREAM"
echo "elevation_stream_sha256=$elevation_stream_sha256"
echo "frontier_baseline_path=$BASELINE"

"$FRONTIER_RUNNER" "$RUN_ID-frontier" "$BASELINE" "${TASKS[@]}" | tee "$FRONTIER_LOG"
frontier_baseline_sha256="$(sha256_file "$BASELINE")"
frontier_baseline_summary_path="$(frontier_summary_from_log "$FRONTIER_LOG" "$OUTDIR/frontier_baseline_summary.json")"
if ! validate_frontier_baseline_summary "$frontier_baseline_summary_path" "$BASELINE" "$frontier_baseline_sha256" "$task_provenance_sha256" "${TASKS[@]}"; then
  echo "frontier baseline summary missing or invalid: $frontier_baseline_summary_path" >&2
  exit 2
fi
if ! frontier_summary_verification="$("$FRONTIER_RUNNER" --verify-summary "$frontier_baseline_summary_path")"; then
  echo "frontier baseline summary receipt verification failed: $frontier_baseline_summary_path" >&2
  printf '%s\n' "$frontier_summary_verification" >&2
  exit 2
fi
frontier_summary_verification_ok="$(report_field "$frontier_summary_verification" frontier_summary_ok false)"
if [[ "$frontier_summary_verification_ok" != "true" ]]; then
  echo "frontier baseline summary did not verify against current evidence: $frontier_baseline_summary_path" >&2
  printf '%s\n' "$frontier_summary_verification" >&2
  exit 2
fi
frontier_baseline_summary_sha256="$(sha256_file "$frontier_baseline_summary_path")"
frontier_summary_report_text="$(frontier_summary_report "$frontier_baseline_summary_path")"
frontier_model="$(report_field "$frontier_summary_report_text" frontier_model "")"
frontier_baseline_role="$(report_field "$frontier_summary_report_text" frontier_baseline_role "")"
frontier_baseline_frozen="$(report_field "$frontier_summary_report_text" frontier_baseline_frozen false)"
frontier_baseline_official_docker="$(report_field "$frontier_summary_report_text" frontier_baseline_official_docker false)"
frontier_baseline_benchmark_label="$(report_field "$frontier_summary_report_text" frontier_baseline_benchmark_label "")"
echo "frontier_model=$frontier_model"
echo "frontier_baseline_role=$frontier_baseline_role"
echo "frontier_baseline_frozen=$frontier_baseline_frozen"
echo "frontier_baseline_official_docker=$frontier_baseline_official_docker"
echo "frontier_baseline_benchmark_label=$frontier_baseline_benchmark_label"
echo "frontier_baseline_summary_path=$frontier_baseline_summary_path"
echo "frontier_baseline_summary_sha256=$frontier_baseline_summary_sha256"
echo "frontier_summary_verification_ok=$frontier_summary_verification_ok"

stream_selftest="$(ATOMIC_ELEVATION_SELECTION_MANIFEST="$MANIFEST" "$ELEVATION_STREAM" --selftest "$WEIGHTS" "$BASELINE" "${TASKS[@]}")"
frontier_receipt_ok="$(printf '%s\n' "$stream_selftest" | awk -F= '/^frontier_baseline_evidence_receipt_ok=/{print $2}' | tail -1)"
elevation_valid_if_run="$(printf '%s\n' "$stream_selftest" | awk -F= '/^elevation_valid_if_run=/{print $2}' | tail -1)"
if [[ "$frontier_receipt_ok" != "true" || "$elevation_valid_if_run" != "true" ]]; then
  echo "frontier receipt/elevation selftest rejected the just-frozen baseline" >&2
  printf '%s\n' "$stream_selftest" >&2
  exit 2
fi
weights_sha256="$(sha256_file "$WEIGHTS")"

ATOMIC_ELEVATION_RUN_ID="$RUN_ID" ATOMIC_ELEVATION_SELECTION_MANIFEST="$MANIFEST" "$ELEVATION_STREAM" "$RUN_TAG" "$BASELINE" "$WEIGHTS" "${TASKS[@]}" | tee "$OUTDIR/elevation_stream.log"

elevation_summary_path="$(elevation_summary_from_log "$OUTDIR/elevation_stream.log" "$HERE/evidence/ELEVATION/$RUN_ID/elevation_summary.json")"
if ! validate_elevation_summary "$elevation_summary_path" "$BASELINE" "$frontier_baseline_sha256" "$selected_task_ids_sha256" "$MANIFEST" "$selection_manifest_sha256" "${TASKS[@]}"; then
  echo "elevation summary missing or invalid: $elevation_summary_path" >&2
  exit 2
fi
elevation_summary_sha256="$(sha256_file "$elevation_summary_path")"
elevation_metric_report_text="$(elevation_metric_report "$elevation_summary_path")"
frontier_baseline_resolved="$(report_field "$elevation_metric_report_text" frontier_baseline_resolved 0)"
frontier_solve_rate="$(report_field "$elevation_metric_report_text" frontier_solve_rate 0.0)"
metric_scope="$(report_field "$elevation_metric_report_text" metric_scope "$METRIC_SCOPE")"
within_task_efficiency_metric_admissible="$(report_field "$elevation_metric_report_text" within_task_efficiency_metric_admissible "$WITHIN_TASK_EFFICIENCY_METRIC_ADMISSIBLE")"
deepseek_control_resolved="$(report_field "$elevation_metric_report_text" deepseek_control_resolved 0)"
deepseek_control_solve_rate="$(report_field "$elevation_metric_report_text" deepseek_control_solve_rate 0.0)"
atomic_substrate_resolved="$(report_field "$elevation_metric_report_text" atomic_substrate_resolved 0)"
student_solve_rate="$(report_field "$elevation_metric_report_text" student_solve_rate 0.0)"
elevation_vs_frontier="$(report_field "$elevation_metric_report_text" elevation_vs_frontier 0)"
elevation_vs_frontier_solve_rate="$(report_field "$elevation_metric_report_text" elevation_vs_frontier_solve_rate 0.0)"
elevation_vs_deepseek_control="$(report_field "$elevation_metric_report_text" elevation_vs_deepseek_control 0)"
elevation_vs_deepseek_control_solve_rate="$(report_field "$elevation_metric_report_text" elevation_vs_deepseek_control_solve_rate 0.0)"
accumulation_index="$(report_field "$elevation_metric_report_text" accumulation_index 0)"
substrate_weight_count="$(report_field "$elevation_metric_report_text" substrate_weight_count 0)"
write_round_receipt_json "$ROUND_RECEIPT" \
  metric=pro_elevation_round \
  metric_claim=false \
  production_ready_to_run="$preflight_production_ready_to_run" \
  ready_blockers="$preflight_ready_blockers" \
  production_ready_blockers="$preflight_production_ready_blockers" \
  metric_admissible="$metric_admissible" \
  production_toolchain_ok="$production_toolchain_ok" \
  run_id="$RUN_ID" \
  benchmark_suite="$BENCHMARK_SUITE" \
  benchmark_dataset_name="$DATASET_NAME" \
  official_benchmark=true \
  metric_scope="$metric_scope" \
  within_task_efficiency_metric_admissible="$within_task_efficiency_metric_admissible" \
  manifest_path="$MANIFEST" \
  selected_task_count="${#TASKS[@]}" \
  selected_task_ids_sha256="$selected_task_ids_sha256" \
  selection_manifest_path="$MANIFEST" \
  selection_manifest_sha256="$selection_manifest_sha256" \
  selection_receipt_ok=true \
  anti_cherry_pick=true \
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
  task_provenance_sha256="$task_provenance_sha256" \
  frontier_baseline_path="$BASELINE" \
  frontier_baseline_sha256="$frontier_baseline_sha256" \
  frontier_model="$frontier_model" \
  frontier_baseline_role="$frontier_baseline_role" \
  frontier_baseline_frozen="$frontier_baseline_frozen" \
  frontier_baseline_official_docker="$frontier_baseline_official_docker" \
  frontier_baseline_benchmark_label="$frontier_baseline_benchmark_label" \
  frontier_baseline_summary_path="$frontier_baseline_summary_path" \
  frontier_baseline_summary_sha256="$frontier_baseline_summary_sha256" \
  frontier_summary_verification_ok="$frontier_summary_verification_ok" \
  frontier_baseline_evidence_receipt_ok="$frontier_receipt_ok" \
  frontier_baseline_resolved="$frontier_baseline_resolved" \
  frontier_solve_rate="$frontier_solve_rate" \
  deepseek_control_resolved="$deepseek_control_resolved" \
  deepseek_control_solve_rate="$deepseek_control_solve_rate" \
  atomic_substrate_resolved="$atomic_substrate_resolved" \
  student_solve_rate="$student_solve_rate" \
  student_model="$STUDENT_MODEL" \
  elevation_vs_frontier="$elevation_vs_frontier" \
  elevation_vs_frontier_solve_rate="$elevation_vs_frontier_solve_rate" \
  elevation_vs_deepseek_control="$elevation_vs_deepseek_control" \
  elevation_vs_deepseek_control_solve_rate="$elevation_vs_deepseek_control_solve_rate" \
  accumulation_index="$accumulation_index" \
  substrate_weight_count="$substrate_weight_count" \
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
printf 'metric=pro_elevation_round metric_claim=false production_ready_to_run=%s ready_blockers=%s production_ready_blockers=%s metric_admissible=%s production_toolchain_ok=%s run_id=%s benchmark_suite=%s benchmark_dataset_name=%s official_benchmark=true metric_scope=%s within_task_efficiency_metric_admissible=%s manifest_path=%s selected_task_count=%s selected_task_ids_sha256=%s selection_manifest_path=%s selection_manifest_sha256=%s selection_receipt_ok=true anti_cherry_pick=true frontier_baseline_runner=%s frontier_baseline_runner_sha256=%s elevation_stream=%s elevation_stream_sha256=%s weights_path=%s weights_sha256=%s preflight_receipt_path=%s preflight_receipt_sha256=%s preflight_verification_ok=%s task_provenance_ok=%s task_provenance_sha256=%s frontier_baseline_path=%s frontier_baseline_sha256=%s frontier_model=%s frontier_baseline_role=%s frontier_baseline_frozen=%s frontier_baseline_official_docker=%s frontier_baseline_benchmark_label=%s frontier_baseline_summary_path=%s frontier_baseline_summary_sha256=%s frontier_summary_verification_ok=%s frontier_baseline_evidence_receipt_ok=%s frontier_baseline_resolved=%s frontier_solve_rate=%s deepseek_control_resolved=%s deepseek_control_solve_rate=%s atomic_substrate_resolved=%s student_solve_rate=%s student_model=%s elevation_vs_frontier=%s elevation_vs_frontier_solve_rate=%s elevation_vs_deepseek_control=%s elevation_vs_deepseek_control_solve_rate=%s accumulation_index=%s substrate_weight_count=%s elevation_valid_if_run=%s elevation_summary_path=%s elevation_summary_sha256=%s round_receipt_path=%s round_receipt_sha256=%s round_receipt_verification_ok=%s\n' \
  "$preflight_production_ready_to_run" "$preflight_ready_blockers" "$preflight_production_ready_blockers" "$metric_admissible" "$production_toolchain_ok" "$RUN_ID" "$BENCHMARK_SUITE" "$DATASET_NAME" "$metric_scope" "$within_task_efficiency_metric_admissible" "$MANIFEST" "${#TASKS[@]}" "$selected_task_ids_sha256" "$MANIFEST" "$selection_manifest_sha256" "$FRONTIER_RUNNER" "$frontier_runner_sha256" "$ELEVATION_STREAM" "$elevation_stream_sha256" "$WEIGHTS" "$weights_sha256" "$PREFLIGHT" "$preflight_receipt_sha256" "$preflight_verification_ok" "$task_provenance_ok" "$task_provenance_sha256" "$BASELINE" "$frontier_baseline_sha256" "$frontier_model" "$frontier_baseline_role" "$frontier_baseline_frozen" "$frontier_baseline_official_docker" "$frontier_baseline_benchmark_label" "$frontier_baseline_summary_path" "$frontier_baseline_summary_sha256" "$frontier_summary_verification_ok" "$frontier_receipt_ok" "$frontier_baseline_resolved" "$frontier_solve_rate" "$deepseek_control_resolved" "$deepseek_control_solve_rate" "$atomic_substrate_resolved" "$student_solve_rate" "$STUDENT_MODEL" "$elevation_vs_frontier" "$elevation_vs_frontier_solve_rate" "$elevation_vs_deepseek_control" "$elevation_vs_deepseek_control_solve_rate" "$accumulation_index" "$substrate_weight_count" "$elevation_valid_if_run" "$elevation_summary_path" "$elevation_summary_sha256" "$ROUND_RECEIPT" "$round_receipt_sha256" "$round_receipt_verification_ok"
