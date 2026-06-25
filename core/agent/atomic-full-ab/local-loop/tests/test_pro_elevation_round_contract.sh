#!/usr/bin/env bash
set -euo pipefail

HERE="/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"
cd "$HERE"

ROUND="$HERE/run_pro_elevation_round.sh"
FRONTIER_RUNNER="$HERE/run_frontier_baseline.sh"
ELEVATION_STREAM="$HERE/run_elevation_stream.sh"
WEIGHTS="$HERE/.corpus/weights.jsonl"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

manifest="$tmp/pro_manifest.json"
cat >"$manifest" <<'JSON'
{
  "anti_leakage": {
    "patch": "omitted",
    "problem_statement": "omitted",
    "test_patch": "omitted"
  },
  "benchmark_label": "SWE-bench-Pro",
  "benchmark_suite": "swe_bench_pro",
  "dataset_name": "ScaleAI/SWE-bench_Pro",
  "dataset_split": "test",
  "eligible_count": 2,
  "metric_claim": false,
  "official_benchmark": true,
  "purpose": "held_out_candidate_manifest_not_elevation_result",
  "rows": [
    {"instance_id": "pro__task-a", "selection_rank_sha256": "001"},
    {"instance_id": "pro__task-b", "selection_rank_sha256": "002"}
  ],
  "selected_count": 2,
  "selected_task_ids": ["pro__task-a", "pro__task-b"],
  "selection_method": "sha256(seed + NUL + instance_id) over official dataset rows; excludes teach task ids",
  "selection_seed": "contract-seed",
  "teach_task_ids": ["teach__task-z"],
  "total_count": 2
}
JSON

selftest="$(ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" "$ROUND" --selftest)"
manifest_sha="$(shasum -a 256 "$manifest" | awk '{print $1}')"
frontier_runner_sha="$(shasum -a 256 "$FRONTIER_RUNNER" | awk '{print $1}')"
elevation_stream_sha="$(shasum -a 256 "$ELEVATION_STREAM" | awk '{print $1}')"
grep -q '^metric=pro_elevation_round$' <<<"$selftest"
grep -q '^metric_claim=false$' <<<"$selftest"
grep -q '^benchmark_suite=swe_bench_pro$' <<<"$selftest"
grep -q '^benchmark_dataset_name=ScaleAI/SWE-bench_Pro$' <<<"$selftest"
grep -q '^official_benchmark=true$' <<<"$selftest"
grep -q '^selected_task_count=2$' <<<"$selftest"
grep -q "^selection_manifest_path=$manifest$" <<<"$selftest"
grep -q "^selection_manifest_sha256=$manifest_sha$" <<<"$selftest"
grep -q '^selection_receipt_ok=true$' <<<"$selftest"
grep -q '^anti_cherry_pick=true$' <<<"$selftest"
grep -q '^requires_deepseek_api_key=true$' <<<"$selftest"
grep -q '^requires_modal_token_id=true$' <<<"$selftest"
grep -q '^requires_modal_token_secret=true$' <<<"$selftest"
grep -q '^requires_rotated_credentials_attestation=true$' <<<"$selftest"
grep -q '^credential_source=env$' <<<"$selftest"
grep -q '^credential_file_allowed=false$' <<<"$selftest"
grep -q "^frontier_baseline_runner=$FRONTIER_RUNNER$" <<<"$selftest"
grep -q "^frontier_baseline_runner_sha256=$frontier_runner_sha$" <<<"$selftest"
grep -q "^elevation_stream=$ELEVATION_STREAM$" <<<"$selftest"
grep -q "^elevation_stream_sha256=$elevation_stream_sha$" <<<"$selftest"
grep -q '^weights_path=' <<<"$selftest"
grep -q '^no_synthetic=true$' <<<"$selftest"
grep -q '^no_replay=true$' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_runner' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_runner_sha256' <<<"$selftest"
grep -q 'summary_fields=.*elevation_stream' <<<"$selftest"
grep -q 'summary_fields=.*elevation_stream_sha256' <<<"$selftest"
grep -q 'summary_fields=.*weights_path' <<<"$selftest"
grep -q 'summary_fields=.*weights_sha256' <<<"$selftest"
grep -q 'summary_fields=.*task_provenance_ok' <<<"$selftest"
grep -q 'summary_fields=.*task_provenance_sha256' <<<"$selftest"
grep -q 'summary_fields=.*selection_manifest_path' <<<"$selftest"
grep -q 'summary_fields=.*selection_manifest_sha256' <<<"$selftest"
grep -q 'summary_fields=.*selection_receipt_ok' <<<"$selftest"
grep -q 'summary_fields=.*anti_cherry_pick' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_path' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_sha256' <<<"$selftest"
grep -q 'summary_fields=.*frontier_model' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_role' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_frozen' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_official_docker' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_benchmark_label' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_summary_path' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_summary_sha256' <<<"$selftest"
grep -q 'summary_fields=.*frontier_summary_verification_ok' <<<"$selftest"
grep -q 'summary_fields=.*preflight_receipt_path' <<<"$selftest"
grep -q 'summary_fields=.*preflight_receipt_sha256' <<<"$selftest"
grep -q 'summary_fields=.*preflight_verification_ok' <<<"$selftest"
grep -q 'summary_fields=.*elevation_summary_path' <<<"$selftest"
grep -q 'summary_fields=.*elevation_summary_sha256' <<<"$selftest"
grep -q 'summary_fields=.*round_receipt_path' <<<"$selftest"
grep -q 'summary_fields=.*round_receipt_sha256' <<<"$selftest"
grep -q 'summary_fields=.*round_receipt_verification_ok' <<<"$selftest"
grep -q 'summary_fields=.*production_ready_to_run' <<<"$selftest"
grep -q 'summary_fields=.*production_toolchain_ok' <<<"$selftest"
grep -q 'summary_fields=.*metric_admissible' <<<"$selftest"
grep -q 'summary_fields=.*metric_scope' <<<"$selftest"
grep -q 'summary_fields=.*within_task_efficiency_metric_admissible' <<<"$selftest"
grep -q 'summary_fields=.*frontier_baseline_resolved' <<<"$selftest"
grep -q 'summary_fields=.*frontier_solve_rate' <<<"$selftest"
grep -q 'summary_fields=.*deepseek_control_resolved' <<<"$selftest"
grep -q 'summary_fields=.*deepseek_control_solve_rate' <<<"$selftest"
grep -q 'summary_fields=.*atomic_substrate_resolved' <<<"$selftest"
grep -q 'summary_fields=.*student_solve_rate' <<<"$selftest"
grep -q 'summary_fields=.*student_model' <<<"$selftest"
grep -q 'summary_fields=.*elevation_vs_frontier' <<<"$selftest"
grep -q 'summary_fields=.*elevation_vs_frontier_solve_rate' <<<"$selftest"
grep -q 'summary_fields=.*elevation_vs_deepseek_control' <<<"$selftest"
grep -q 'summary_fields=.*elevation_vs_deepseek_control_solve_rate' <<<"$selftest"
grep -q 'summary_fields=.*accumulation_index' <<<"$selftest"
grep -q 'summary_fields=.*substrate_weight_count' <<<"$selftest"

preflight_json="$tmp/preflight.json"
preflight="$(ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" "$ROUND" --preflight "$preflight_json")"
grep -q '^metric=pro_elevation_preflight$' <<<"$preflight"
grep -q '^metric_claim=false$' <<<"$preflight"
grep -q '^official_benchmark=true$' <<<"$preflight"
grep -q '^selected_task_count=2$' <<<"$preflight"
grep -q '^selection_receipt_ok=true$' <<<"$preflight"
grep -q '^anti_cherry_pick=true$' <<<"$preflight"
grep -q '^deepseek_api_key_present=false$' <<<"$preflight"
grep -q '^modal_token_id_present=false$' <<<"$preflight"
grep -q '^modal_token_secret_present=false$' <<<"$preflight"
grep -q '^modal_credentials_present=false$' <<<"$preflight"
grep -q '^deepseek_api_key_format_ok=false$' <<<"$preflight"
grep -q '^modal_token_id_format_ok=false$' <<<"$preflight"
grep -q '^modal_token_secret_format_ok=false$' <<<"$preflight"
grep -q '^modal_credentials_format_ok=false$' <<<"$preflight"
grep -q '^credential_format_bypassed_by_test_runner=false$' <<<"$preflight"
grep -q '^credential_format_ok=false$' <<<"$preflight"
grep -q '^production_credential_format_ok=false$' <<<"$preflight"
grep -q '^credential_rotation_attested=false$' <<<"$preflight"
grep -q '^credential_rotation_attestation_bypassed_by_test_runner=false$' <<<"$preflight"
grep -q '^credential_rotation_attestation_ok=false$' <<<"$preflight"
grep -q '^deepseek_auth_ok=false$' <<<"$preflight"
grep -q '^deepseek_balance_available=false$' <<<"$preflight"
grep -q '^official_deepseek_api_preflight_ok=false$' <<<"$preflight"
grep -q '^deepseek_api_preflight_ok=false$' <<<"$preflight"
grep -q '^deepseek_api_preflight_bypassed_by_test_runner=false$' <<<"$preflight"
grep -q '^modal_cli_present=' <<<"$preflight"
grep -q '^modal_auth_ok=false$' <<<"$preflight"
grep -q '^official_modal_preflight_ok=false$' <<<"$preflight"
grep -q '^modal_preflight_ok=false$' <<<"$preflight"
grep -q '^modal_preflight_bypassed_by_test_runner=false$' <<<"$preflight"
grep -q '^credential_source=env$' <<<"$preflight"
grep -q '^credential_file_allowed=false$' <<<"$preflight"
grep -q "^frontier_baseline_runner=$FRONTIER_RUNNER$" <<<"$preflight"
grep -q "^frontier_baseline_runner_sha256=$frontier_runner_sha$" <<<"$preflight"
grep -q "^elevation_stream=$ELEVATION_STREAM$" <<<"$preflight"
grep -q "^elevation_stream_sha256=$elevation_stream_sha$" <<<"$preflight"
grep -q '^task_layout_ok=false$' <<<"$preflight"
grep -q '^task_provenance_ok=false$' <<<"$preflight"
grep -q '^task_provenance_sha256=$' <<<"$preflight"
grep -q '^suite_pristine_layout_ok=false$' <<<"$preflight"
grep -q '^swebench_import_ok=' <<<"$preflight"
grep -q '^docker_api_ok=' <<<"$preflight"
grep -q '^official_scorer_preflight_ok=' <<<"$preflight"
grep -q '^scorer_preflight_ok=' <<<"$preflight"
grep -q '^ready_to_run=false$' <<<"$preflight"
grep -q '^production_ready_to_run=false$' <<<"$preflight"
grep -q '^no_model_run=true$' <<<"$preflight"
grep -q '^no_scorer_run=true$' <<<"$preflight"
grep -q '"metric": "pro_elevation_preflight"' "$preflight_json"
grep -q '"metric_claim": false' "$preflight_json"
grep -q '"deepseek_api_key_present": false' "$preflight_json"
grep -q '"modal_token_id_present": false' "$preflight_json"
grep -q '"modal_token_secret_present": false' "$preflight_json"
grep -q '"modal_credentials_present": false' "$preflight_json"
grep -q '"deepseek_api_key_format_ok": false' "$preflight_json"
grep -q '"modal_token_id_format_ok": false' "$preflight_json"
grep -q '"modal_token_secret_format_ok": false' "$preflight_json"
grep -q '"modal_credentials_format_ok": false' "$preflight_json"
grep -q '"credential_format_bypassed_by_test_runner": false' "$preflight_json"
grep -q '"credential_format_ok": false' "$preflight_json"
grep -q '"production_credential_format_ok": false' "$preflight_json"
grep -q '"credential_rotation_attested": false' "$preflight_json"
grep -q '"credential_rotation_attestation_bypassed_by_test_runner": false' "$preflight_json"
grep -q '"credential_rotation_attestation_ok": false' "$preflight_json"
grep -q '"deepseek_auth_ok": false' "$preflight_json"
grep -q '"deepseek_balance_available": false' "$preflight_json"
grep -q '"official_deepseek_api_preflight_ok": false' "$preflight_json"
grep -q '"deepseek_api_preflight_ok": false' "$preflight_json"
grep -q '"deepseek_api_preflight_bypassed_by_test_runner": false' "$preflight_json"
grep -q '"modal_cli_present": ' "$preflight_json"
grep -q '"modal_auth_ok": false' "$preflight_json"
grep -q '"official_modal_preflight_ok": false' "$preflight_json"
grep -q '"modal_preflight_ok": false' "$preflight_json"
grep -q '"modal_preflight_bypassed_by_test_runner": false' "$preflight_json"
grep -q '"credential_source": "env"' "$preflight_json"
grep -q '"credential_file_allowed": false' "$preflight_json"
grep -q "\"frontier_baseline_runner_sha256\": \"$frontier_runner_sha\"" "$preflight_json"
grep -q "\"elevation_stream_sha256\": \"$elevation_stream_sha\"" "$preflight_json"
grep -q '"task_provenance_ok": false' "$preflight_json"
grep -q '"task_provenance_sha256": ""' "$preflight_json"
grep -q '"ready_to_run": false' "$preflight_json"
grep -q '"production_ready_to_run": false' "$preflight_json"
if grep -q 'DEEPSEEK_API_KEY\|MODAL_TOKEN' "$preflight_json"; then
  echo "preflight receipt must not serialize secret names or values" >&2
  exit 1
fi

blocked_ready_json="$tmp/blocked-ready.json"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" "$ROUND" --ready "$blocked_ready_json" >"$tmp/blocked-ready.out" 2>"$tmp/blocked-ready.err"; then
  echo "expected --ready to exit nonzero when preflight is not ready" >&2
  exit 1
fi
grep -q '^metric=pro_elevation_preflight$' "$tmp/blocked-ready.out"
grep -q '^ready_to_run=false$' "$tmp/blocked-ready.out"
grep -q '^production_ready_to_run=false$' "$tmp/blocked-ready.out"
grep -q '^no_model_run=true$' "$tmp/blocked-ready.out"
grep -q '^no_scorer_run=true$' "$tmp/blocked-ready.out"
grep -q '"ready_to_run": false' "$blocked_ready_json"
grep -q '"production_ready_to_run": false' "$blocked_ready_json"

bad_manifest="$tmp/verified_manifest.json"
cat >"$bad_manifest" <<'JSON'
{
  "benchmark_suite": "swe_bench_verified",
  "dataset_name": "princeton-nlp/SWE-bench_Verified",
  "official_benchmark": false,
  "selected_task_ids": ["verified__task"]
}
JSON
if ATOMIC_PRO_ELEVATION_MANIFEST="$bad_manifest" DEEPSEEK_API_KEY=dummy "$ROUND" BADROUND >"$tmp/bad.out" 2>"$tmp/bad.err"; then
  echo "expected non-Pro manifest to be rejected" >&2
  exit 1
fi
grep -q 'official SWE-Bench Pro manifest required' "$tmp/bad.err"

nokey_outroot="$tmp/nokey-out"
mkdir -p "$nokey_outroot"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_ELEVATION_OUTROOT="$nokey_outroot" \
ATOMIC_PRO_ELEVATION_RUN_ID="nokey-preflight" \
  "$ROUND" NOKEY >"$tmp/nokey.out" 2>"$tmp/nokey.err"; then
  echo "expected missing DEEPSEEK_API_KEY to be rejected by preflight" >&2
  exit 1
fi
grep -q 'Pro elevation preflight failed' "$tmp/nokey.err"
grep -q 'deepseek_api_key_present=false' "$tmp/nokey.err"
grep -q 'ready_to_run=false' "$tmp/nokey.err"
grep -q 'production_ready_to_run=false' "$tmp/nokey.err"
grep -q '"deepseek_api_key_present": false' "$nokey_outroot/nokey-preflight/preflight.json"
grep -q '"deepseek_api_key_format_ok": false' "$nokey_outroot/nokey-preflight/preflight.json"
grep -q '"credential_format_ok": false' "$nokey_outroot/nokey-preflight/preflight.json"
grep -q '"production_credential_format_ok": false' "$nokey_outroot/nokey-preflight/preflight.json"
grep -q '"credential_rotation_attestation_ok": false' "$nokey_outroot/nokey-preflight/preflight.json"
grep -q '"deepseek_api_preflight_ok": false' "$nokey_outroot/nokey-preflight/preflight.json"
grep -q '"modal_preflight_ok": false' "$nokey_outroot/nokey-preflight/preflight.json"
grep -q '"ready_to_run": false' "$nokey_outroot/nokey-preflight/preflight.json"
grep -q '"production_ready_to_run": false' "$nokey_outroot/nokey-preflight/preflight.json"

fake_provenance_sha="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
fake_frontier="$tmp/fake_frontier.sh"
cat >"$fake_frontier" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--selftest" ]; then
  echo 'task_layout_ok=true'
  echo 'task_provenance_ok=true'
  echo 'task_provenance_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  echo 'suite_pristine_layout_ok=true'
  exit 0
fi
if [ "${1:-}" = "--verify-summary" ]; then
  summary="${2:-}"
  python3 - "$summary" <<'PYVERIFYFRONTIERSUMMARY'
import hashlib
import json
import sys
from pathlib import Path

summary = Path(sys.argv[1])
ok = False
baseline_sha_ok = False
schema_ok = False
try:
    data = json.loads(summary.read_text(encoding="utf-8"))
    schema_ok = isinstance(data, dict)
    baseline = Path(data.get("frontier_baseline_path", ""))
    if baseline.is_file():
        baseline_sha_ok = hashlib.sha256(baseline.read_bytes()).hexdigest() == data.get("frontier_baseline_sha256")
    ok = (
        data.get("metric") == "frontier_baseline_receipt"
        and data.get("metric_claim") is False
        and data.get("benchmark_suite") == "swe_bench_pro"
        and data.get("benchmark_dataset_name") == "ScaleAI/SWE-bench_Pro"
        and data.get("benchmark_label") == "SWE-bench-Pro"
        and data.get("baseline_role") == "frontier"
        and data.get("frozen") is True
        and data.get("official_docker") is True
        and data.get("frontier_baseline_evidence_receipt_ok") is True
        and baseline_sha_ok
    )
except Exception:
    pass
print("metric=frontier_baseline_summary_verification")
print("metric_claim=false")
print(f"frontier_summary_path={summary}")
print(f"frontier_summary_exists={'true' if summary.is_file() else 'false'}")
print(f"frontier_summary_schema_ok={'true' if schema_ok else 'false'}")
print(f"frontier_summary_matches_current={'true' if ok else 'false'}")
print(f"frontier_summary_ok={'true' if ok else 'false'}")
print(f"frontier_baseline_sha256_ok={'true' if baseline_sha_ok else 'false'}")
print("frontier_baseline_evidence_receipt_ok=true")
print("no_model_run=true")
print("no_scorer_run=true")
raise SystemExit(0 if ok else 2)
PYVERIFYFRONTIERSUMMARY
  exit $?
fi
printf 'frontier_args=%s\n' "$*" >"$ATOMIC_FAKE_FRONTIER_ARGS"
out="$2"
summary="${ATOMIC_FAKE_FRONTIER_SUMMARY:-$(dirname "$out")/frontier_baseline_summary.json}"
mkdir -p "$(dirname "$out")" "$(dirname "$summary")"
printf '{"baseline_role":"frontier","frontier_receipt":{"format":"swebench_pro_frontier_baseline_v1"}}\n' >"$out"
task_hash="$(printf 'pro__task-a\npro__task-b' | shasum -a 256 | awk '{print $1}')"
baseline_sha="$(shasum -a 256 "$out" | awk '{print $1}')"
printf '{"baseline_role":"frontier","benchmark_dataset_name":"ScaleAI/SWE-bench_Pro","benchmark_label":"SWE-bench-Pro","benchmark_suite":"swe_bench_pro","frontier_baseline_evidence_receipt_ok":true,"frontier_baseline_path":"%s","frontier_baseline_sha256":"%s","frontier_model":"fake-frontier","frozen":true,"metric":"frontier_baseline_receipt","metric_claim":false,"official_benchmark":true,"official_docker":true,"sample_failures":0,"score_failures":0,"suite_preflight_ok":true,"task_ids":["pro__task-a","pro__task-b"],"task_ids_sha256":"%s","task_provenance_ok":true,"task_provenance_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}\n' "$out" "$baseline_sha" "$task_hash" >"$summary"
printf 'metric=frontier_baseline_receipt metric_claim=false official_benchmark=true tasks=2 frontier_baseline_path=%s frontier_baseline_sha256=%s frontier_baseline_evidence_receipt_ok=true sample_failures=0 score_failures=0 summary=%s\n' "$out" "$baseline_sha" "$summary"
SH
chmod +x "$fake_frontier"

fake_stream="$tmp/fake_stream.sh"
cat >"$fake_stream" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--selftest" ]; then
  echo 'frontier_baseline_evidence_receipt_ok=true'
  echo 'elevation_valid_if_run=true'
  exit 0
fi
printf 'stream_args=%s\n' "$*" >"$ATOMIC_FAKE_STREAM_ARGS"
mkdir -p "$ATOMIC_FAKE_ELEVATION_OUT"
task_hash="$(printf 'pro__task-a\npro__task-b' | shasum -a 256 | awk '{print $1}')"
baseline_sha="$(shasum -a 256 "$2" | awk '{print $1}')"
selection_manifest="${ATOMIC_ELEVATION_SELECTION_MANIFEST:-}"
selection_manifest_sha="$(shasum -a 256 "$selection_manifest" | awk '{print $1}')"
printf '{"metric":"elevation","metric_claim":false,"benchmark_suite":"swe_bench_pro","benchmark_dataset_name":"ScaleAI/SWE-bench_Pro","official_benchmark":true,"metric_scope":"paired_frontier_solve_rate_delta","within_task_efficiency_metric_admissible":false,"task_ids":["pro__task-a","pro__task-b"],"task_count":2,"selected_task_ids_sha256":"%s","selection_manifest_path":"%s","selection_manifest_sha256":"%s","selection_receipt_ok":true,"anti_cherry_pick":true,"frontier_baseline_path":"%s","frontier_baseline_sha256":"%s","frontier_baseline_role":"frontier","frontier_baseline_frozen":true,"frontier_baseline_official_docker":true,"frontier_baseline_benchmark_label":"SWE-bench-Pro","frontier_baseline_resolved":1,"frontier_solve_rate":0.5,"deepseek_control_resolved":0,"deepseek_control_solve_rate":0.0,"atomic_substrate_resolved":1,"student_solve_rate":0.5,"elevation_vs_frontier":0,"elevation_vs_frontier_solve_rate":0.0,"elevation_vs_deepseek_control":1,"elevation_vs_deepseek_control_solve_rate":0.5,"accumulation_index":14,"substrate_weight_count":9,"student_model":"deepseek-v4-pro","elevation_valid":true,"task_provenance_ok":true,"suite_preflight_ok":true,"frontier_baseline_evidence_receipt_ok":true,"frontier_baseline_provenance_ok":true,"teacher_atomic":true,"anti_replay":true,"distinct_tasks":true,"sample_timeouts":0,"score_failures":0,"reused_samples":0,"rerun_timeout_samples":0}\n' "$task_hash" "$selection_manifest" "$selection_manifest_sha" "$2" "$baseline_sha" >"$ATOMIC_FAKE_ELEVATION_OUT/elevation_summary.json"
echo "elevation_summary=$ATOMIC_FAKE_ELEVATION_OUT/elevation_summary.json"
SH
chmod +x "$fake_stream"
fake_frontier_sha="$(shasum -a 256 "$fake_frontier" | awk '{print $1}')"
fake_stream_sha="$(shasum -a 256 "$fake_stream" | awk '{print $1}')"

missing_modal_preflight_json="$tmp/missing-modal-preflight.json"
missing_modal_preflight="$(ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
ATOMIC_PRO_ELEVATION_ALLOW_TEST_RUNNERS=1 \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" --preflight "$missing_modal_preflight_json")"
grep -q '^deepseek_api_key_present=true$' <<<"$missing_modal_preflight"
grep -q '^modal_token_id_present=false$' <<<"$missing_modal_preflight"
grep -q '^modal_token_secret_present=false$' <<<"$missing_modal_preflight"
grep -q '^modal_credentials_present=false$' <<<"$missing_modal_preflight"
grep -q '^deepseek_api_key_format_ok=false$' <<<"$missing_modal_preflight"
grep -q '^modal_token_id_format_ok=false$' <<<"$missing_modal_preflight"
grep -q '^modal_token_secret_format_ok=false$' <<<"$missing_modal_preflight"
grep -q '^modal_credentials_format_ok=false$' <<<"$missing_modal_preflight"
grep -q '^credential_format_bypassed_by_test_runner=true$' <<<"$missing_modal_preflight"
grep -q '^credential_format_ok=true$' <<<"$missing_modal_preflight"
grep -q '^production_credential_format_ok=false$' <<<"$missing_modal_preflight"
grep -q '^credential_rotation_attested=false$' <<<"$missing_modal_preflight"
grep -q '^credential_rotation_attestation_bypassed_by_test_runner=true$' <<<"$missing_modal_preflight"
grep -q '^credential_rotation_attestation_ok=true$' <<<"$missing_modal_preflight"
grep -q '^deepseek_auth_ok=false$' <<<"$missing_modal_preflight"
grep -q '^deepseek_balance_available=false$' <<<"$missing_modal_preflight"
grep -q '^official_deepseek_api_preflight_ok=false$' <<<"$missing_modal_preflight"
grep -q '^deepseek_api_preflight_bypassed_by_test_runner=true$' <<<"$missing_modal_preflight"
grep -q '^deepseek_api_preflight_ok=true$' <<<"$missing_modal_preflight"
grep -q '^modal_auth_ok=false$' <<<"$missing_modal_preflight"
grep -q '^official_modal_preflight_ok=false$' <<<"$missing_modal_preflight"
grep -q '^modal_preflight_bypassed_by_test_runner=true$' <<<"$missing_modal_preflight"
grep -q '^modal_preflight_ok=true$' <<<"$missing_modal_preflight"
grep -q '^scorer_preflight_bypassed_by_test_runner=true$' <<<"$missing_modal_preflight"
grep -q '^scorer_preflight_ok=true$' <<<"$missing_modal_preflight"
grep -q '^official_scorer_preflight_ok=false$' <<<"$missing_modal_preflight"
grep -q '^ready_to_run=false$' <<<"$missing_modal_preflight"
grep -q '^production_ready_to_run=false$' <<<"$missing_modal_preflight"
grep -q '"modal_token_id_present": false' "$missing_modal_preflight_json"
grep -q '"modal_token_secret_present": false' "$missing_modal_preflight_json"
grep -q '"modal_credentials_present": false' "$missing_modal_preflight_json"
grep -q '"credential_format_bypassed_by_test_runner": true' "$missing_modal_preflight_json"
grep -q '"credential_format_ok": true' "$missing_modal_preflight_json"
grep -q '"production_credential_format_ok": false' "$missing_modal_preflight_json"
grep -q '"credential_rotation_attested": false' "$missing_modal_preflight_json"
grep -q '"credential_rotation_attestation_bypassed_by_test_runner": true' "$missing_modal_preflight_json"
grep -q '"credential_rotation_attestation_ok": true' "$missing_modal_preflight_json"
grep -q '"deepseek_api_preflight_bypassed_by_test_runner": true' "$missing_modal_preflight_json"
grep -q '"deepseek_api_preflight_ok": true' "$missing_modal_preflight_json"
grep -q '"official_modal_preflight_ok": false' "$missing_modal_preflight_json"
grep -q '"modal_preflight_bypassed_by_test_runner": true' "$missing_modal_preflight_json"
grep -q '"modal_preflight_ok": true' "$missing_modal_preflight_json"

export MODAL_TOKEN_ID=dummy-modal-token-id
export MODAL_TOKEN_SECRET=dummy-modal-token-secret

override_preflight_json="$tmp/override-preflight.json"
override_preflight="$(ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" --preflight "$override_preflight_json")"
grep -q '^runner_policy_ok=false$' <<<"$override_preflight"
grep -q '^scorer_preflight_bypassed_by_test_runner=false$' <<<"$override_preflight"
grep -q '^scorer_preflight_ok=' <<<"$override_preflight"
grep -q '^official_scorer_preflight_ok=' <<<"$override_preflight"
grep -q '^deepseek_api_key_format_ok=false$' <<<"$override_preflight"
grep -q '^modal_token_id_format_ok=false$' <<<"$override_preflight"
grep -q '^modal_token_secret_format_ok=false$' <<<"$override_preflight"
grep -q '^modal_credentials_format_ok=false$' <<<"$override_preflight"
grep -q '^credential_format_bypassed_by_test_runner=false$' <<<"$override_preflight"
grep -q '^credential_format_ok=false$' <<<"$override_preflight"
grep -q '^production_credential_format_ok=false$' <<<"$override_preflight"
grep -q '^credential_rotation_attested=false$' <<<"$override_preflight"
grep -q '^credential_rotation_attestation_bypassed_by_test_runner=false$' <<<"$override_preflight"
grep -q '^credential_rotation_attestation_ok=false$' <<<"$override_preflight"
grep -q '^deepseek_auth_ok=false$' <<<"$override_preflight"
grep -q '^deepseek_balance_available=false$' <<<"$override_preflight"
grep -q '^official_deepseek_api_preflight_ok=false$' <<<"$override_preflight"
grep -q '^deepseek_api_preflight_bypassed_by_test_runner=false$' <<<"$override_preflight"
grep -q '^deepseek_api_preflight_ok=false$' <<<"$override_preflight"
grep -q '^modal_auth_ok=false$' <<<"$override_preflight"
grep -q '^official_modal_preflight_ok=false$' <<<"$override_preflight"
grep -q '^modal_preflight_bypassed_by_test_runner=false$' <<<"$override_preflight"
grep -q '^modal_preflight_ok=false$' <<<"$override_preflight"
grep -q '^test_runner_override_allowed=false$' <<<"$override_preflight"
grep -q '^ready_to_run=false$' <<<"$override_preflight"
grep -q '^production_ready_to_run=false$' <<<"$override_preflight"
grep -q '"runner_policy_ok": false' "$override_preflight_json"
grep -q '"credential_format_bypassed_by_test_runner": false' "$override_preflight_json"
grep -q '"credential_format_ok": false' "$override_preflight_json"
grep -q '"production_credential_format_ok": false' "$override_preflight_json"
grep -q '"credential_rotation_attestation_ok": false' "$override_preflight_json"
grep -q '"deepseek_api_preflight_ok": false' "$override_preflight_json"
grep -q '"official_modal_preflight_ok": false' "$override_preflight_json"
grep -q '"modal_preflight_bypassed_by_test_runner": false' "$override_preflight_json"
grep -q '"modal_preflight_ok": false' "$override_preflight_json"
grep -q '"ready_to_run": false' "$override_preflight_json"
grep -q '"production_ready_to_run": false' "$override_preflight_json"

ready_preflight_json="$tmp/ready-preflight.json"
ready_preflight="$(ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
ATOMIC_PRO_ELEVATION_ALLOW_TEST_RUNNERS=1 \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" --preflight "$ready_preflight_json")"
grep -q '^deepseek_api_key_present=true$' <<<"$ready_preflight"
grep -q '^modal_token_id_present=true$' <<<"$ready_preflight"
grep -q '^modal_token_secret_present=true$' <<<"$ready_preflight"
grep -q '^modal_credentials_present=true$' <<<"$ready_preflight"
grep -q '^deepseek_api_key_format_ok=false$' <<<"$ready_preflight"
grep -q '^modal_token_id_format_ok=false$' <<<"$ready_preflight"
grep -q '^modal_token_secret_format_ok=false$' <<<"$ready_preflight"
grep -q '^modal_credentials_format_ok=false$' <<<"$ready_preflight"
grep -q '^credential_format_bypassed_by_test_runner=true$' <<<"$ready_preflight"
grep -q '^credential_format_ok=true$' <<<"$ready_preflight"
grep -q '^production_credential_format_ok=false$' <<<"$ready_preflight"
grep -q '^credential_rotation_attested=false$' <<<"$ready_preflight"
grep -q '^credential_rotation_attestation_bypassed_by_test_runner=true$' <<<"$ready_preflight"
grep -q '^credential_rotation_attestation_ok=true$' <<<"$ready_preflight"
grep -q '^deepseek_auth_ok=false$' <<<"$ready_preflight"
grep -q '^deepseek_balance_available=false$' <<<"$ready_preflight"
grep -q '^official_deepseek_api_preflight_ok=false$' <<<"$ready_preflight"
grep -q '^deepseek_api_preflight_bypassed_by_test_runner=true$' <<<"$ready_preflight"
grep -q '^deepseek_api_preflight_ok=true$' <<<"$ready_preflight"
grep -q '^modal_auth_ok=false$' <<<"$ready_preflight"
grep -q '^official_modal_preflight_ok=false$' <<<"$ready_preflight"
grep -q '^modal_preflight_bypassed_by_test_runner=true$' <<<"$ready_preflight"
grep -q '^modal_preflight_ok=true$' <<<"$ready_preflight"
grep -q '^credential_source=env$' <<<"$ready_preflight"
grep -q '^credential_file_allowed=false$' <<<"$ready_preflight"
grep -q '^runner_policy_ok=true$' <<<"$ready_preflight"
grep -q '^scorer_preflight_bypassed_by_test_runner=true$' <<<"$ready_preflight"
grep -q '^scorer_preflight_ok=true$' <<<"$ready_preflight"
grep -q '^official_scorer_preflight_ok=false$' <<<"$ready_preflight"
grep -q '^test_runner_override_allowed=true$' <<<"$ready_preflight"
grep -q "^selection_manifest_path=$manifest$" <<<"$ready_preflight"
grep -q "^selection_manifest_sha256=$manifest_sha$" <<<"$ready_preflight"
grep -q '^frontier_runner_ok=true$' <<<"$ready_preflight"
grep -q "^frontier_baseline_runner=$fake_frontier$" <<<"$ready_preflight"
grep -q "^frontier_baseline_runner_sha256=$fake_frontier_sha$" <<<"$ready_preflight"
grep -q '^elevation_stream_ok=true$' <<<"$ready_preflight"
grep -q "^elevation_stream=$fake_stream$" <<<"$ready_preflight"
grep -q "^elevation_stream_sha256=$fake_stream_sha$" <<<"$ready_preflight"
grep -q '^weights_ok=true$' <<<"$ready_preflight"
grep -q '^task_layout_ok=true$' <<<"$ready_preflight"
grep -q '^task_provenance_ok=true$' <<<"$ready_preflight"
grep -q "^task_provenance_sha256=$fake_provenance_sha$" <<<"$ready_preflight"
grep -q '^suite_pristine_layout_ok=true$' <<<"$ready_preflight"
grep -q '^ready_to_run=true$' <<<"$ready_preflight"
grep -q '^production_ready_to_run=false$' <<<"$ready_preflight"
grep -q '"ready_to_run": true' "$ready_preflight_json"
grep -q '"production_ready_to_run": false' "$ready_preflight_json"
grep -q "\"selection_manifest_path\": \"$manifest\"" "$ready_preflight_json"
grep -q "\"selection_manifest_sha256\": \"$manifest_sha\"" "$ready_preflight_json"
grep -q '"modal_token_id_present": true' "$ready_preflight_json"
grep -q '"modal_token_secret_present": true' "$ready_preflight_json"
grep -q '"modal_credentials_present": true' "$ready_preflight_json"
grep -q '"deepseek_api_key_format_ok": false' "$ready_preflight_json"
grep -q '"modal_token_id_format_ok": false' "$ready_preflight_json"
grep -q '"modal_token_secret_format_ok": false' "$ready_preflight_json"
grep -q '"modal_credentials_format_ok": false' "$ready_preflight_json"
grep -q '"credential_format_bypassed_by_test_runner": true' "$ready_preflight_json"
grep -q '"credential_format_ok": true' "$ready_preflight_json"
grep -q '"production_credential_format_ok": false' "$ready_preflight_json"
grep -q '"credential_rotation_attested": false' "$ready_preflight_json"
grep -q '"credential_rotation_attestation_bypassed_by_test_runner": true' "$ready_preflight_json"
grep -q '"credential_rotation_attestation_ok": true' "$ready_preflight_json"
grep -q '"deepseek_api_preflight_bypassed_by_test_runner": true' "$ready_preflight_json"
grep -q '"deepseek_api_preflight_ok": true' "$ready_preflight_json"
grep -q '"official_modal_preflight_ok": false' "$ready_preflight_json"
grep -q '"modal_preflight_bypassed_by_test_runner": true' "$ready_preflight_json"
grep -q '"modal_preflight_ok": true' "$ready_preflight_json"
grep -q "\"frontier_baseline_runner_sha256\": \"$fake_frontier_sha\"" "$ready_preflight_json"
grep -q "\"elevation_stream_sha256\": \"$fake_stream_sha\"" "$ready_preflight_json"
grep -q '"task_provenance_ok": true' "$ready_preflight_json"
grep -q "\"task_provenance_sha256\": \"$fake_provenance_sha\"" "$ready_preflight_json"
grep -q '"no_model_run": true' "$ready_preflight_json"
grep -q '"no_scorer_run": true' "$ready_preflight_json"

fake_hex_key="0123456789abcdef0123456789abcdef"
fake_modal_id="syntheticModalId12345"
fake_modal_value="syntheticModalValue12345"
valid_format_preflight_json="$tmp/valid-format-preflight.json"
valid_format_preflight="$(ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
ATOMIC_PRO_ELEVATION_ALLOW_TEST_RUNNERS=1 \
DEEPSEEK_API_KEY="sk-$fake_hex_key" \
MODAL_TOKEN_ID="ak-$fake_modal_id" \
MODAL_TOKEN_SECRET="as-$fake_modal_value" \
  "$ROUND" --preflight "$valid_format_preflight_json")"
grep -q '^deepseek_api_key_format_ok=true$' <<<"$valid_format_preflight"
grep -q '^modal_token_id_format_ok=true$' <<<"$valid_format_preflight"
grep -q '^modal_token_secret_format_ok=true$' <<<"$valid_format_preflight"
grep -q '^modal_credentials_format_ok=true$' <<<"$valid_format_preflight"
grep -q '^credential_format_bypassed_by_test_runner=true$' <<<"$valid_format_preflight"
grep -q '^credential_format_ok=true$' <<<"$valid_format_preflight"
grep -q '^production_credential_format_ok=true$' <<<"$valid_format_preflight"
grep -q '^credential_rotation_attested=false$' <<<"$valid_format_preflight"
grep -q '^credential_rotation_attestation_bypassed_by_test_runner=true$' <<<"$valid_format_preflight"
grep -q '^credential_rotation_attestation_ok=true$' <<<"$valid_format_preflight"
grep -q '^deepseek_auth_ok=false$' <<<"$valid_format_preflight"
grep -q '^deepseek_balance_available=false$' <<<"$valid_format_preflight"
grep -q '^official_deepseek_api_preflight_ok=false$' <<<"$valid_format_preflight"
grep -q '^deepseek_api_preflight_bypassed_by_test_runner=true$' <<<"$valid_format_preflight"
grep -q '^deepseek_api_preflight_ok=true$' <<<"$valid_format_preflight"
grep -q '^modal_auth_ok=false$' <<<"$valid_format_preflight"
grep -q '^official_modal_preflight_ok=false$' <<<"$valid_format_preflight"
grep -q '^modal_preflight_bypassed_by_test_runner=true$' <<<"$valid_format_preflight"
grep -q '^modal_preflight_ok=true$' <<<"$valid_format_preflight"
grep -q '^ready_to_run=true$' <<<"$valid_format_preflight"
grep -q '^production_ready_to_run=false$' <<<"$valid_format_preflight"
grep -q '"production_credential_format_ok": true' "$valid_format_preflight_json"
grep -q '"credential_rotation_attestation_ok": true' "$valid_format_preflight_json"
grep -q '"official_deepseek_api_preflight_ok": false' "$valid_format_preflight_json"
grep -q '"deepseek_api_preflight_ok": true' "$valid_format_preflight_json"
grep -q '"official_modal_preflight_ok": false' "$valid_format_preflight_json"
grep -q '"modal_preflight_bypassed_by_test_runner": true' "$valid_format_preflight_json"
grep -q '"modal_preflight_ok": true' "$valid_format_preflight_json"

verify_ready="$(ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
ATOMIC_PRO_ELEVATION_ALLOW_TEST_RUNNERS=1 \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" --verify-preflight "$ready_preflight_json")"
grep -q '^metric=pro_elevation_preflight_verification$' <<<"$verify_ready"
grep -q '^metric_claim=false$' <<<"$verify_ready"
grep -q '^preflight_receipt_ok=true$' <<<"$verify_ready"
grep -q "^selection_manifest_path=$manifest$" <<<"$verify_ready"
grep -q "^selection_manifest_sha256=$manifest_sha$" <<<"$verify_ready"
grep -q '^selection_receipt_ok=true$' <<<"$verify_ready"
grep -q '^anti_cherry_pick=true$' <<<"$verify_ready"
grep -q '^receipt_ready_to_run=true$' <<<"$verify_ready"
grep -q '^current_ready_to_run=true$' <<<"$verify_ready"
grep -q '^receipt_production_ready_to_run=false$' <<<"$verify_ready"
grep -q '^current_production_ready_to_run=false$' <<<"$verify_ready"
grep -q '^receipt_matches_current=true$' <<<"$verify_ready"
grep -q '^no_model_run=true$' <<<"$verify_ready"
grep -q '^no_scorer_run=true$' <<<"$verify_ready"

ready_cmd_json="$tmp/ready-cmd.json"
ready_cmd_out="$(ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
ATOMIC_PRO_ELEVATION_ALLOW_TEST_RUNNERS=1 \
ATOMIC_FAKE_FRONTIER_ARGS="$tmp/ready-frontier.args" \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" --ready "$ready_cmd_json")"
grep -q '^metric=pro_elevation_preflight$' <<<"$ready_cmd_out"
grep -q '^ready_to_run=true$' <<<"$ready_cmd_out"
grep -q '^production_ready_to_run=false$' <<<"$ready_cmd_out"
grep -q '^no_model_run=true$' <<<"$ready_cmd_out"
grep -q '^no_scorer_run=true$' <<<"$ready_cmd_out"
grep -q '"ready_to_run": true' "$ready_cmd_json"
grep -q '"production_ready_to_run": false' "$ready_cmd_json"
test ! -f "$tmp/ready-frontier.args"

production_ready_cmd_json="$tmp/production-ready-cmd.json"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
ATOMIC_PRO_ELEVATION_ALLOW_TEST_RUNNERS=1 \
ATOMIC_FAKE_FRONTIER_ARGS="$tmp/production-ready-frontier.args" \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" --production-ready "$production_ready_cmd_json" >"$tmp/production-ready.out" 2>"$tmp/production-ready.err"; then
  echo "expected --production-ready to reject test-runner readiness" >&2
  exit 1
fi
grep -q '^metric=pro_elevation_preflight$' "$tmp/production-ready.out"
grep -q '^ready_to_run=true$' "$tmp/production-ready.out"
grep -q '^production_ready_to_run=false$' "$tmp/production-ready.out"
grep -q '^no_model_run=true$' "$tmp/production-ready.out"
grep -q '^no_scorer_run=true$' "$tmp/production-ready.out"
grep -q '"ready_to_run": true' "$production_ready_cmd_json"
grep -q '"production_ready_to_run": false' "$production_ready_cmd_json"
test ! -f "$tmp/production-ready-frontier.args"

if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
ATOMIC_PRO_ELEVATION_ALLOW_TEST_RUNNERS=1 \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" --verify-production-ready "$production_ready_cmd_json" >"$tmp/verify-production-ready.out" 2>"$tmp/verify-production-ready.err"; then
  echo "expected production-ready verifier to reject test-runner readiness" >&2
  exit 1
fi
grep -q '^metric=pro_elevation_production_ready_verification$' "$tmp/verify-production-ready.out"
grep -q '^metric_claim=false$' "$tmp/verify-production-ready.out"
grep -q "^selection_manifest_path=$manifest$" "$tmp/verify-production-ready.out"
grep -q "^selection_manifest_sha256=$manifest_sha$" "$tmp/verify-production-ready.out"
grep -q '^selection_receipt_ok=true$' "$tmp/verify-production-ready.out"
grep -q '^anti_cherry_pick=true$' "$tmp/verify-production-ready.out"
grep -q '^preflight_receipt_exists=true$' "$tmp/verify-production-ready.out"
grep -q '^preflight_receipt_schema_ok=true$' "$tmp/verify-production-ready.out"
grep -q '^preflight_receipt_ok=true$' "$tmp/verify-production-ready.out"
grep -q '^receipt_ready_to_run=true$' "$tmp/verify-production-ready.out"
grep -q '^current_ready_to_run=true$' "$tmp/verify-production-ready.out"
grep -q '^receipt_production_ready_to_run=false$' "$tmp/verify-production-ready.out"
grep -q '^current_production_ready_to_run=false$' "$tmp/verify-production-ready.out"
grep -q '^receipt_matches_current=true$' "$tmp/verify-production-ready.out"
grep -q '^production_ready_receipt_ok=false$' "$tmp/verify-production-ready.out"
grep -q '^no_model_run=true$' "$tmp/verify-production-ready.out"
grep -q '^no_scorer_run=true$' "$tmp/verify-production-ready.out"

tampered_preflight_json="$tmp/tampered-preflight.json"
sed 's/"selected_task_ids_sha256": "[^"]*"/"selected_task_ids_sha256": "stale"/' "$ready_preflight_json" >"$tampered_preflight_json"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
ATOMIC_PRO_ELEVATION_ALLOW_TEST_RUNNERS=1 \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" --verify-preflight "$tampered_preflight_json" >"$tmp/tampered-verify.out" 2>"$tmp/tampered-verify.err"; then
  echo "expected tampered preflight receipt to be rejected" >&2
  exit 1
fi
grep -q '^preflight_receipt_ok=false$' "$tmp/tampered-verify.out"
grep -q '^receipt_matches_current=false$' "$tmp/tampered-verify.out"

tampered_selection_manifest_json="$tmp/tampered-selection-manifest-preflight.json"
sed 's/"selection_manifest_sha256": "[^"]*"/"selection_manifest_sha256": "stale"/' "$ready_preflight_json" >"$tampered_selection_manifest_json"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
ATOMIC_PRO_ELEVATION_ALLOW_TEST_RUNNERS=1 \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" --verify-preflight "$tampered_selection_manifest_json" >"$tmp/tampered-selection-manifest-verify.out" 2>"$tmp/tampered-selection-manifest-verify.err"; then
  echo "expected tampered preflight selection manifest hash to be rejected" >&2
  exit 1
fi
grep -q '^preflight_receipt_ok=false$' "$tmp/tampered-selection-manifest-verify.out"
grep -q '^receipt_matches_current=false$' "$tmp/tampered-selection-manifest-verify.out"

tampered_toolchain_json="$tmp/tampered-toolchain-preflight.json"
sed 's/"frontier_baseline_runner_sha256": "[^"]*"/"frontier_baseline_runner_sha256": "stale"/' "$ready_preflight_json" >"$tampered_toolchain_json"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
ATOMIC_PRO_ELEVATION_ALLOW_TEST_RUNNERS=1 \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" --verify-preflight "$tampered_toolchain_json" >"$tmp/tampered-toolchain-verify.out" 2>"$tmp/tampered-toolchain-verify.err"; then
  echo "expected tampered toolchain hash to be rejected" >&2
  exit 1
fi
grep -q '^preflight_receipt_ok=false$' "$tmp/tampered-toolchain-verify.out"
grep -q '^receipt_matches_current=false$' "$tmp/tampered-toolchain-verify.out"

tampered_provenance_json="$tmp/tampered-provenance-preflight.json"
sed 's/"task_provenance_sha256": "[^"]*"/"task_provenance_sha256": "stale"/' "$ready_preflight_json" >"$tampered_provenance_json"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
ATOMIC_PRO_ELEVATION_ALLOW_TEST_RUNNERS=1 \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" --verify-preflight "$tampered_provenance_json" >"$tmp/tampered-provenance-verify.out" 2>"$tmp/tampered-provenance-verify.err"; then
  echo "expected tampered task provenance hash to be rejected" >&2
  exit 1
fi
grep -q '^preflight_receipt_ok=false$' "$tmp/tampered-provenance-verify.out"
grep -q '^receipt_matches_current=false$' "$tmp/tampered-provenance-verify.out"

if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
  "$ROUND" --verify-preflight "$preflight_json" >"$tmp/blocked-verify.out" 2>"$tmp/blocked-verify.err"; then
  echo "expected blocked preflight receipt to fail verification" >&2
  exit 1
fi
grep -q '^preflight_receipt_ok=false$' "$tmp/blocked-verify.out"
grep -q '^receipt_ready_to_run=false$' "$tmp/blocked-verify.out"
grep -q '^current_ready_to_run=false$' "$tmp/blocked-verify.out"
grep -q '^receipt_production_ready_to_run=false$' "$tmp/blocked-verify.out"
grep -q '^current_production_ready_to_run=false$' "$tmp/blocked-verify.out"

bad_layout_frontier="$tmp/bad_layout_frontier.sh"
cat >"$bad_layout_frontier" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--selftest" ]; then
  echo 'task_layout_ok=false'
  echo 'suite_pristine_layout_ok=true'
  exit 0
fi
printf 'frontier sampling should not run after failed preflight\n' >"$ATOMIC_BAD_FRONTIER_MARKER"
exit 99
SH
chmod +x "$bad_layout_frontier"
bad_outroot="$tmp/bad-out"
mkdir -p "$bad_outroot"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$bad_layout_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
ATOMIC_PRO_ELEVATION_ALLOW_TEST_RUNNERS=1 \
ATOMIC_PRO_ELEVATION_OUTROOT="$bad_outroot" \
ATOMIC_PRO_ELEVATION_RUN_ID="bad-preflight" \
ATOMIC_BAD_FRONTIER_MARKER="$tmp/bad-frontier.marker" \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" BADPREFLIGHT >"$tmp/badpre.out" 2>"$tmp/badpre.err"; then
  echo "expected failed preflight to abort the Pro round" >&2
  exit 1
fi
grep -q 'Pro elevation preflight failed' "$tmp/badpre.err"
test ! -f "$tmp/bad-frontier.marker"
grep -q 'ready_to_run=false' "$tmp/badpre.err"
grep -q '"ready_to_run": false' "$bad_outroot/bad-preflight/preflight.json"

bad_provenance_frontier="$tmp/bad_provenance_frontier.sh"
cat >"$bad_provenance_frontier" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--selftest" ]; then
  echo 'task_layout_ok=true'
  echo 'task_provenance_ok=false'
  echo 'suite_pristine_layout_ok=true'
  exit 0
fi
printf 'frontier sampling should not run after bad task provenance\n' >"$ATOMIC_BAD_PROVENANCE_MARKER"
exit 99
SH
chmod +x "$bad_provenance_frontier"
bad_provenance_outroot="$tmp/bad-provenance-out"
mkdir -p "$bad_provenance_outroot"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$bad_provenance_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
ATOMIC_PRO_ELEVATION_ALLOW_TEST_RUNNERS=1 \
ATOMIC_PRO_ELEVATION_OUTROOT="$bad_provenance_outroot" \
ATOMIC_PRO_ELEVATION_RUN_ID="bad-provenance-preflight" \
ATOMIC_BAD_PROVENANCE_MARKER="$tmp/bad-provenance-frontier.marker" \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" BADPROVENANCE >"$tmp/bad-provenance.out" 2>"$tmp/bad-provenance.err"; then
  echo "expected bad task provenance to abort the Pro round" >&2
  exit 1
fi
grep -q 'Pro elevation preflight failed' "$tmp/bad-provenance.err"
test ! -f "$tmp/bad-provenance-frontier.marker"
grep -q 'task_provenance_ok=false' "$tmp/bad-provenance.err"
grep -q 'ready_to_run=false' "$tmp/bad-provenance.err"
grep -q '"task_provenance_ok": false' "$bad_provenance_outroot/bad-provenance-preflight/preflight.json"
grep -q '"ready_to_run": false' "$bad_provenance_outroot/bad-provenance-preflight/preflight.json"

missing_summary_stream="$tmp/missing_summary_stream.sh"
cat >"$missing_summary_stream" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--selftest" ]; then
  echo 'frontier_baseline_evidence_receipt_ok=true'
  echo 'elevation_valid_if_run=true'
  exit 0
fi
echo "elevation_summary=$ATOMIC_MISSING_SUMMARY_PATH"
SH
chmod +x "$missing_summary_stream"
missing_summary_outroot="$tmp/missing-summary-out"
mkdir -p "$missing_summary_outroot"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$missing_summary_stream" \
ATOMIC_PRO_ELEVATION_ALLOW_TEST_RUNNERS=1 \
ATOMIC_PRO_ELEVATION_OUTROOT="$missing_summary_outroot" \
ATOMIC_PRO_ELEVATION_RUN_ID="missing-summary" \
ATOMIC_FAKE_FRONTIER_ARGS="$tmp/missing-frontier.args" \
ATOMIC_MISSING_SUMMARY_PATH="$tmp/missing-summary.json" \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" MISSINGSUMMARY >"$tmp/missing-summary.out" 2>"$tmp/missing-summary.err"; then
  echo "expected missing elevation summary to abort the Pro round" >&2
  exit 1
fi
grep -q 'elevation summary missing or invalid' "$tmp/missing-summary.err"

legacy_summary_stream="$tmp/legacy_summary_stream.sh"
cat >"$legacy_summary_stream" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--selftest" ]; then
  echo 'frontier_baseline_evidence_receipt_ok=true'
  echo 'elevation_valid_if_run=true'
  exit 0
fi
mkdir -p "$ATOMIC_LEGACY_SUMMARY_OUT"
printf '{"metric":"elevation","metric_claim":false,"benchmark_suite":"swe_bench_pro","benchmark_dataset_name":"ScaleAI/SWE-bench_Pro","official_benchmark":true,"task_ids":["pro__task-a","pro__task-b"],"elevation_valid":true,"task_provenance_ok":true,"suite_preflight_ok":true,"frontier_baseline_evidence_receipt_ok":true,"frontier_baseline_provenance_ok":true,"teacher_atomic":true,"anti_replay":true,"distinct_tasks":true}\n' >"$ATOMIC_LEGACY_SUMMARY_OUT/elevation_summary.json"
echo "elevation_summary=$ATOMIC_LEGACY_SUMMARY_OUT/elevation_summary.json"
SH
chmod +x "$legacy_summary_stream"
legacy_summary_outroot="$tmp/legacy-summary-out"
mkdir -p "$legacy_summary_outroot"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$legacy_summary_stream" \
ATOMIC_PRO_ELEVATION_ALLOW_TEST_RUNNERS=1 \
ATOMIC_PRO_ELEVATION_OUTROOT="$legacy_summary_outroot" \
ATOMIC_PRO_ELEVATION_RUN_ID="legacy-summary" \
ATOMIC_FAKE_FRONTIER_ARGS="$tmp/legacy-frontier.args" \
ATOMIC_LEGACY_SUMMARY_OUT="$tmp/legacy-summary" \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" LEGACYSUMMARY >"$tmp/legacy-summary.out" 2>"$tmp/legacy-summary.err"; then
  echo "expected elevation summary without paired hashes to abort the Pro round" >&2
  exit 1
fi
grep -q 'elevation summary missing or invalid' "$tmp/legacy-summary.err"

bad_evidence_stream="$tmp/bad_evidence_stream.sh"
cat >"$bad_evidence_stream" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--selftest" ]; then
  echo 'frontier_baseline_evidence_receipt_ok=true'
  echo 'elevation_valid_if_run=true'
  exit 0
fi
mkdir -p "$ATOMIC_BAD_EVIDENCE_OUT"
task_hash="$(printf 'pro__task-a\npro__task-b' | shasum -a 256 | awk '{print $1}')"
baseline_sha="$(shasum -a 256 "$2" | awk '{print $1}')"
printf '{"metric":"elevation","metric_claim":false,"benchmark_suite":"swe_bench_pro","benchmark_dataset_name":"ScaleAI/SWE-bench_Pro","official_benchmark":true,"task_ids":["pro__task-a","pro__task-b"],"selected_task_ids_sha256":"%s","frontier_baseline_path":"%s","frontier_baseline_sha256":"%s","elevation_valid":true,"task_provenance_ok":true,"suite_preflight_ok":true,"frontier_baseline_evidence_receipt_ok":true,"frontier_baseline_provenance_ok":true,"teacher_atomic":true,"anti_replay":false,"distinct_tasks":true}\n' "$task_hash" "$2" "$baseline_sha" >"$ATOMIC_BAD_EVIDENCE_OUT/elevation_summary.json"
echo "elevation_summary=$ATOMIC_BAD_EVIDENCE_OUT/elevation_summary.json"
SH
chmod +x "$bad_evidence_stream"
bad_evidence_outroot="$tmp/bad-evidence-out"
mkdir -p "$bad_evidence_outroot"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$bad_evidence_stream" \
ATOMIC_PRO_ELEVATION_ALLOW_TEST_RUNNERS=1 \
ATOMIC_PRO_ELEVATION_OUTROOT="$bad_evidence_outroot" \
ATOMIC_PRO_ELEVATION_RUN_ID="bad-evidence" \
ATOMIC_FAKE_FRONTIER_ARGS="$tmp/bad-evidence-frontier.args" \
ATOMIC_BAD_EVIDENCE_OUT="$tmp/bad-evidence" \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" BADEVIDENCE >"$tmp/bad-evidence.out" 2>"$tmp/bad-evidence.err"; then
  echo "expected anti-circularity-invalid elevation summary to abort the Pro round" >&2
  exit 1
fi
grep -q 'elevation summary missing or invalid' "$tmp/bad-evidence.err"

wrong_student_summary_stream="$tmp/wrong_student_summary_stream.sh"
cat >"$wrong_student_summary_stream" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--selftest" ]; then
  echo 'frontier_baseline_evidence_receipt_ok=true'
  echo 'elevation_valid_if_run=true'
  exit 0
fi
mkdir -p "$ATOMIC_WRONG_STUDENT_SUMMARY_OUT"
task_hash="$(printf 'pro__task-a\npro__task-b' | shasum -a 256 | awk '{print $1}')"
baseline_sha="$(shasum -a 256 "$2" | awk '{print $1}')"
printf '{"metric":"elevation","metric_claim":false,"benchmark_suite":"swe_bench_pro","benchmark_dataset_name":"ScaleAI/SWE-bench_Pro","official_benchmark":true,"task_ids":["pro__task-a","pro__task-b"],"task_count":2,"selected_task_ids_sha256":"%s","frontier_baseline_path":"%s","frontier_baseline_sha256":"%s","frontier_baseline_resolved":1,"frontier_solve_rate":0.5,"deepseek_control_resolved":0,"deepseek_control_solve_rate":0.0,"atomic_substrate_resolved":1,"student_solve_rate":0.5,"elevation_vs_frontier":0,"elevation_vs_frontier_solve_rate":0.0,"elevation_vs_deepseek_control":1,"elevation_vs_deepseek_control_solve_rate":0.5,"student_model":"not-deepseek-v4-pro","elevation_valid":true,"task_provenance_ok":true,"suite_preflight_ok":true,"frontier_baseline_evidence_receipt_ok":true,"frontier_baseline_provenance_ok":true,"teacher_atomic":true,"anti_replay":true,"distinct_tasks":true,"sample_timeouts":0,"score_failures":0,"reused_samples":0,"rerun_timeout_samples":0}\n' "$task_hash" "$2" "$baseline_sha" >"$ATOMIC_WRONG_STUDENT_SUMMARY_OUT/elevation_summary.json"
echo "elevation_summary=$ATOMIC_WRONG_STUDENT_SUMMARY_OUT/elevation_summary.json"
SH
chmod +x "$wrong_student_summary_stream"
wrong_student_summary_outroot="$tmp/wrong-student-summary-out"
mkdir -p "$wrong_student_summary_outroot"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$wrong_student_summary_stream" \
ATOMIC_PRO_ELEVATION_ALLOW_TEST_RUNNERS=1 \
ATOMIC_PRO_ELEVATION_OUTROOT="$wrong_student_summary_outroot" \
ATOMIC_PRO_ELEVATION_RUN_ID="wrong-student-summary" \
ATOMIC_FAKE_FRONTIER_ARGS="$tmp/wrong-student-frontier.args" \
ATOMIC_WRONG_STUDENT_SUMMARY_OUT="$tmp/wrong-student-summary" \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" WRONGSTUDENTSUMMARY >"$tmp/wrong-student-summary.out" 2>"$tmp/wrong-student-summary.err"; then
  echo "expected elevation summary with non-DeepSeek student model to abort the Pro round" >&2
  exit 1
fi
grep -q 'elevation summary missing or invalid' "$tmp/wrong-student-summary.err"

claimful_summary_stream="$tmp/claimful_summary_stream.sh"
cat >"$claimful_summary_stream" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--selftest" ]; then
  echo 'frontier_baseline_evidence_receipt_ok=true'
  echo 'elevation_valid_if_run=true'
  exit 0
fi
mkdir -p "$ATOMIC_CLAIMFUL_SUMMARY_OUT"
task_hash="$(printf 'pro__task-a\npro__task-b' | shasum -a 256 | awk '{print $1}')"
baseline_sha="$(shasum -a 256 "$2" | awk '{print $1}')"
printf '{"metric":"elevation","metric_claim":true,"benchmark_suite":"swe_bench_pro","benchmark_dataset_name":"ScaleAI/SWE-bench_Pro","official_benchmark":true,"task_ids":["pro__task-a","pro__task-b"],"selected_task_ids_sha256":"%s","frontier_baseline_path":"%s","frontier_baseline_sha256":"%s","elevation_valid":true,"task_provenance_ok":true,"suite_preflight_ok":true,"frontier_baseline_evidence_receipt_ok":true,"frontier_baseline_provenance_ok":true,"teacher_atomic":true,"anti_replay":true,"distinct_tasks":true,"sample_timeouts":0,"score_failures":0,"reused_samples":0,"rerun_timeout_samples":0}\n' "$task_hash" "$2" "$baseline_sha" >"$ATOMIC_CLAIMFUL_SUMMARY_OUT/elevation_summary.json"
echo "elevation_summary=$ATOMIC_CLAIMFUL_SUMMARY_OUT/elevation_summary.json"
SH
chmod +x "$claimful_summary_stream"
claimful_summary_outroot="$tmp/claimful-summary-out"
mkdir -p "$claimful_summary_outroot"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$claimful_summary_stream" \
ATOMIC_PRO_ELEVATION_ALLOW_TEST_RUNNERS=1 \
ATOMIC_PRO_ELEVATION_OUTROOT="$claimful_summary_outroot" \
ATOMIC_PRO_ELEVATION_RUN_ID="claimful-summary" \
ATOMIC_FAKE_FRONTIER_ARGS="$tmp/claimful-frontier.args" \
ATOMIC_CLAIMFUL_SUMMARY_OUT="$tmp/claimful-summary" \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" CLAIMFULSUMMARY >"$tmp/claimful-summary.out" 2>"$tmp/claimful-summary.err"; then
  echo "expected claimful elevation summary to abort the Pro round" >&2
  exit 1
fi
grep -q 'elevation summary missing or invalid' "$tmp/claimful-summary.err"

missing_rate_summary_stream="$tmp/missing_rate_summary_stream.sh"
cat >"$missing_rate_summary_stream" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--selftest" ]; then
  echo 'frontier_baseline_evidence_receipt_ok=true'
  echo 'elevation_valid_if_run=true'
  exit 0
fi
mkdir -p "$ATOMIC_MISSING_RATE_SUMMARY_OUT"
task_hash="$(printf 'pro__task-a\npro__task-b' | shasum -a 256 | awk '{print $1}')"
baseline_sha="$(shasum -a 256 "$2" | awk '{print $1}')"
printf '{"metric":"elevation","metric_claim":false,"benchmark_suite":"swe_bench_pro","benchmark_dataset_name":"ScaleAI/SWE-bench_Pro","official_benchmark":true,"task_ids":["pro__task-a","pro__task-b"],"task_count":2,"selected_task_ids_sha256":"%s","frontier_baseline_path":"%s","frontier_baseline_sha256":"%s","frontier_baseline_resolved":1,"deepseek_control_resolved":0,"atomic_substrate_resolved":1,"elevation_vs_frontier":0,"elevation_vs_deepseek_control":1,"elevation_valid":true,"task_provenance_ok":true,"suite_preflight_ok":true,"frontier_baseline_evidence_receipt_ok":true,"frontier_baseline_provenance_ok":true,"teacher_atomic":true,"anti_replay":true,"distinct_tasks":true,"sample_timeouts":0,"score_failures":0,"reused_samples":0,"rerun_timeout_samples":0}\n' "$task_hash" "$2" "$baseline_sha" >"$ATOMIC_MISSING_RATE_SUMMARY_OUT/elevation_summary.json"
echo "elevation_summary=$ATOMIC_MISSING_RATE_SUMMARY_OUT/elevation_summary.json"
SH
chmod +x "$missing_rate_summary_stream"
missing_rate_summary_outroot="$tmp/missing-rate-summary-out"
mkdir -p "$missing_rate_summary_outroot"
if ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$missing_rate_summary_stream" \
ATOMIC_PRO_ELEVATION_ALLOW_TEST_RUNNERS=1 \
ATOMIC_PRO_ELEVATION_OUTROOT="$missing_rate_summary_outroot" \
ATOMIC_PRO_ELEVATION_RUN_ID="missing-rate-summary" \
ATOMIC_FAKE_FRONTIER_ARGS="$tmp/missing-rate-frontier.args" \
ATOMIC_MISSING_RATE_SUMMARY_OUT="$tmp/missing-rate-summary" \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" MISSINGRATESUMMARY >"$tmp/missing-rate-summary.out" 2>"$tmp/missing-rate-summary.err"; then
  echo "expected elevation summary without paired solve-rate fields to abort the Pro round" >&2
  exit 1
fi
grep -q 'elevation summary missing or invalid' "$tmp/missing-rate-summary.err"

outroot="$tmp/out"
mkdir -p "$outroot"
ATOMIC_PRO_ELEVATION_MANIFEST="$manifest" \
ATOMIC_PRO_FRONTIER_RUNNER="$fake_frontier" \
ATOMIC_PRO_ELEVATION_STREAM="$fake_stream" \
ATOMIC_PRO_ELEVATION_ALLOW_TEST_RUNNERS=1 \
ATOMIC_PRO_ELEVATION_OUTROOT="$outroot" \
ATOMIC_PRO_ELEVATION_RUN_ID="round-contract" \
ATOMIC_FAKE_FRONTIER_ARGS="$tmp/frontier.args" \
ATOMIC_FAKE_STREAM_ARGS="$tmp/stream.args" \
ATOMIC_FAKE_ELEVATION_OUT="$tmp/fake-elevation" \
DEEPSEEK_API_KEY=dummy \
  "$ROUND" ROUNDTEST >"$tmp/round.out"

grep -q 'frontier_args=round-contract-frontier' "$tmp/frontier.args"
grep -q 'pro__task-a' "$tmp/frontier.args"
grep -q 'pro__task-b' "$tmp/frontier.args"
grep -q 'stream_args=ROUNDTEST' "$tmp/stream.args"
grep -q 'pro__task-a' "$tmp/stream.args"
grep -q 'pro__task-b' "$tmp/stream.args"
grep -q '^metric=pro_elevation_round metric_claim=false' "$tmp/round.out"
grep -q "manifest_path=$manifest" "$tmp/round.out"
grep -q "selection_manifest_path=$manifest" "$tmp/round.out"
grep -q "selection_manifest_sha256=$manifest_sha" "$tmp/round.out"
grep -q 'selection_receipt_ok=true' "$tmp/round.out"
grep -q 'anti_cherry_pick=true' "$tmp/round.out"
grep -q "frontier_baseline_runner=$fake_frontier" "$tmp/round.out"
grep -q "frontier_baseline_runner_sha256=$fake_frontier_sha" "$tmp/round.out"
grep -q "elevation_stream=$fake_stream" "$tmp/round.out"
grep -q "elevation_stream_sha256=$fake_stream_sha" "$tmp/round.out"
weights_sha="$(shasum -a 256 "$WEIGHTS" | awk '{print $1}')"
grep -q "weights_path=$WEIGHTS" "$tmp/round.out"
grep -q "weights_sha256=$weights_sha" "$tmp/round.out"
task_ids_sha="$(printf 'pro__task-a\npro__task-b' | shasum -a 256 | awk '{print $1}')"
grep -q "selected_task_ids_sha256=$task_ids_sha" "$tmp/round.out"
grep -q 'task_provenance_ok=true' "$tmp/round.out"
grep -q "task_provenance_sha256=$fake_provenance_sha" "$tmp/round.out"
grep -q 'frontier_baseline_evidence_receipt_ok=true' "$tmp/round.out"
grep -q 'frontier_baseline_role=frontier' "$tmp/round.out"
grep -q 'frontier_baseline_frozen=true' "$tmp/round.out"
grep -q 'frontier_baseline_official_docker=true' "$tmp/round.out"
grep -q 'frontier_baseline_benchmark_label=SWE-bench-Pro' "$tmp/round.out"
grep -q 'production_ready_to_run=false' "$tmp/round.out"
grep -q 'production_toolchain_ok=false' "$tmp/round.out"
grep -q 'metric_admissible=false' "$tmp/round.out"
grep -q 'frontier_summary_verification_ok=true' "$tmp/round.out"
grep -q 'metric_scope=paired_frontier_solve_rate_delta' "$tmp/round.out"
grep -q 'within_task_efficiency_metric_admissible=false' "$tmp/round.out"
grep -q 'frontier_baseline_resolved=1' "$tmp/round.out"
grep -q 'frontier_solve_rate=0.5' "$tmp/round.out"
grep -q 'deepseek_control_resolved=0' "$tmp/round.out"
grep -q 'deepseek_control_solve_rate=0.0' "$tmp/round.out"
grep -q 'atomic_substrate_resolved=1' "$tmp/round.out"
grep -q 'student_solve_rate=0.5' "$tmp/round.out"
grep -q 'student_model=deepseek-v4-pro' "$tmp/round.out"
grep -q 'elevation_vs_frontier=0' "$tmp/round.out"
grep -q 'elevation_vs_frontier_solve_rate=0.0' "$tmp/round.out"
grep -q 'elevation_vs_deepseek_control=1' "$tmp/round.out"
grep -q 'elevation_vs_deepseek_control_solve_rate=0.5' "$tmp/round.out"
grep -q 'accumulation_index=14' "$tmp/round.out"
grep -q 'substrate_weight_count=9' "$tmp/round.out"
baseline_sha="$(shasum -a 256 "$outroot/round-contract/frontier_baseline.json" | awk '{print $1}')"
grep -q "frontier_baseline_sha256=$baseline_sha" "$tmp/round.out"
frontier_summary="$outroot/round-contract/frontier_baseline_summary.json"
test -f "$frontier_summary"
frontier_summary_sha="$(shasum -a 256 "$frontier_summary" | awk '{print $1}')"
grep -q "frontier_model=fake-frontier" "$tmp/round.out"
grep -q "frontier_baseline_summary_path=$frontier_summary" "$tmp/round.out"
grep -q "frontier_baseline_summary_sha256=$frontier_summary_sha" "$tmp/round.out"
grep -q 'elevation_valid_if_run=true' "$tmp/round.out"
grep -q 'preflight_receipt_path=' "$tmp/round.out"
preflight_sha="$(shasum -a 256 "$outroot/round-contract/preflight.json" | awk '{print $1}')"
grep -q "preflight_receipt_sha256=$preflight_sha" "$tmp/round.out"
grep -q 'preflight_verification_ok=true' "$tmp/round.out"
grep -q 'production_ready_to_run=false' "$tmp/round.out"
grep -q "elevation_summary_path=$tmp/fake-elevation/elevation_summary.json" "$tmp/round.out"
summary_sha="$(shasum -a 256 "$tmp/fake-elevation/elevation_summary.json" | awk '{print $1}')"
grep -q "elevation_summary_sha256=$summary_sha" "$tmp/round.out"
round_receipt="$outroot/round-contract/round_receipt.json"
test -f "$round_receipt"
round_receipt_sha="$(shasum -a 256 "$round_receipt" | awk '{print $1}')"
grep -q "round_receipt_path=$round_receipt" "$tmp/round.out"
grep -q "round_receipt_sha256=$round_receipt_sha" "$tmp/round.out"
grep -q 'round_receipt_verification_ok=true' "$tmp/round.out"
grep -q '"metric": "pro_elevation_round"' "$round_receipt"
grep -q '"metric_claim": false' "$round_receipt"
grep -q '"benchmark_suite": "swe_bench_pro"' "$round_receipt"
grep -q '"benchmark_dataset_name": "ScaleAI/SWE-bench_Pro"' "$round_receipt"
grep -q '"official_benchmark": true' "$round_receipt"
grep -q "\"manifest_path\": \"$manifest\"" "$round_receipt"
grep -q "\"selection_manifest_path\": \"$manifest\"" "$round_receipt"
grep -q "\"selection_manifest_sha256\": \"$manifest_sha\"" "$round_receipt"
grep -q '"selection_receipt_ok": true' "$round_receipt"
grep -q '"anti_cherry_pick": true' "$round_receipt"
grep -q "\"selected_task_ids_sha256\": \"$task_ids_sha\"" "$round_receipt"
grep -q '"task_provenance_ok": true' "$round_receipt"
grep -q "\"task_provenance_sha256\": \"$fake_provenance_sha\"" "$round_receipt"
grep -q "\"frontier_baseline_runner_sha256\": \"$fake_frontier_sha\"" "$round_receipt"
grep -q "\"elevation_stream_sha256\": \"$fake_stream_sha\"" "$round_receipt"
grep -q "\"weights_sha256\": \"$weights_sha\"" "$round_receipt"
grep -q "\"preflight_receipt_sha256\": \"$preflight_sha\"" "$round_receipt"
grep -q "\"frontier_baseline_sha256\": \"$baseline_sha\"" "$round_receipt"
grep -q '"frontier_model": "fake-frontier"' "$round_receipt"
grep -q "\"frontier_baseline_summary_path\": \"$frontier_summary\"" "$round_receipt"
grep -q "\"frontier_baseline_summary_sha256\": \"$frontier_summary_sha\"" "$round_receipt"
grep -q '"frontier_summary_verification_ok": true' "$round_receipt"
grep -q "\"elevation_summary_sha256\": \"$summary_sha\"" "$round_receipt"
grep -q '"frontier_baseline_evidence_receipt_ok": true' "$round_receipt"
grep -q '"frontier_baseline_role": "frontier"' "$round_receipt"
grep -q '"frontier_baseline_frozen": true' "$round_receipt"
grep -q '"frontier_baseline_official_docker": true' "$round_receipt"
grep -q '"frontier_baseline_benchmark_label": "SWE-bench-Pro"' "$round_receipt"
grep -q '"frontier_baseline_resolved": 1' "$round_receipt"
grep -q '"frontier_solve_rate": 0.5' "$round_receipt"
grep -q '"deepseek_control_resolved": 0' "$round_receipt"
grep -q '"deepseek_control_solve_rate": 0.0' "$round_receipt"
grep -q '"atomic_substrate_resolved": 1' "$round_receipt"
grep -q '"student_solve_rate": 0.5' "$round_receipt"
grep -q '"student_model": "deepseek-v4-pro"' "$round_receipt"
grep -q '"elevation_vs_frontier": 0' "$round_receipt"
grep -q '"elevation_vs_frontier_solve_rate": 0.0' "$round_receipt"
grep -q '"elevation_vs_deepseek_control": 1' "$round_receipt"
grep -q '"elevation_vs_deepseek_control_solve_rate": 0.5' "$round_receipt"
grep -q '"accumulation_index": 14' "$round_receipt"
grep -q '"substrate_weight_count": 9' "$round_receipt"
grep -q '"elevation_valid_if_run": true' "$round_receipt"
grep -q '"production_ready_to_run": false' "$round_receipt"
grep -q '"production_toolchain_ok": false' "$round_receipt"
grep -q '"metric_admissible": false' "$round_receipt"
grep -q '"metric_scope": "paired_frontier_solve_rate_delta"' "$round_receipt"
grep -q '"within_task_efficiency_metric_admissible": false' "$round_receipt"
grep -q '"task_ids": \[' "$round_receipt"
grep -q '"pro__task-a"' "$round_receipt"
grep -q '"pro__task-b"' "$round_receipt"
if grep -q 'DEEPSEEK_API_KEY\|MODAL_TOKEN' "$round_receipt"; then
  echo "round receipt must not serialize secret names or values" >&2
  exit 1
fi
verify_round="$("$ROUND" --verify-round-receipt "$round_receipt")"
grep -q '^metric=pro_elevation_round_receipt_verification$' <<<"$verify_round"
grep -q '^metric_claim=false$' <<<"$verify_round"
grep -q "^round_receipt_path=$round_receipt$" <<<"$verify_round"
grep -q "^selection_manifest_path=$manifest$" <<<"$verify_round"
grep -q "^selection_manifest_sha256=$manifest_sha$" <<<"$verify_round"
grep -q '^selection_receipt_ok=true$' <<<"$verify_round"
grep -q '^anti_cherry_pick=true$' <<<"$verify_round"
grep -q '^round_receipt_exists=true$' <<<"$verify_round"
grep -q '^round_receipt_schema_ok=true$' <<<"$verify_round"
grep -q '^round_receipt_artifact_hashes_ok=true$' <<<"$verify_round"
grep -q '^round_receipt_task_ids_ok=true$' <<<"$verify_round"
grep -q '^round_receipt_ok=true$' <<<"$verify_round"
grep -q '^frontier_baseline_role=frontier$' <<<"$verify_round"
grep -q '^frontier_baseline_frozen=true$' <<<"$verify_round"
grep -q '^frontier_baseline_official_docker=true$' <<<"$verify_round"
grep -q '^frontier_baseline_benchmark_label=SWE-bench-Pro$' <<<"$verify_round"
grep -q '^frontier_summary_verification_ok=true$' <<<"$verify_round"
grep -q '^production_ready_to_run=false$' <<<"$verify_round"
grep -q '^production_toolchain_ok=false$' <<<"$verify_round"
grep -q '^metric_admissible=false$' <<<"$verify_round"
grep -q '^metric_scope=paired_frontier_solve_rate_delta$' <<<"$verify_round"
grep -q '^within_task_efficiency_metric_admissible=false$' <<<"$verify_round"
grep -q '^frontier_model=fake-frontier$' <<<"$verify_round"
grep -q '^frontier_baseline_resolved=1$' <<<"$verify_round"
grep -q '^frontier_solve_rate=0.5$' <<<"$verify_round"
grep -q '^deepseek_control_resolved=0$' <<<"$verify_round"
grep -q '^deepseek_control_solve_rate=0.0$' <<<"$verify_round"
grep -q '^atomic_substrate_resolved=1$' <<<"$verify_round"
grep -q '^student_solve_rate=0.5$' <<<"$verify_round"
grep -q '^student_model=deepseek-v4-pro$' <<<"$verify_round"
grep -q '^elevation_vs_frontier=0$' <<<"$verify_round"
grep -q '^elevation_vs_frontier_solve_rate=0.0$' <<<"$verify_round"
grep -q '^elevation_vs_deepseek_control=1$' <<<"$verify_round"
grep -q '^elevation_vs_deepseek_control_solve_rate=0.5$' <<<"$verify_round"
grep -q '^accumulation_index=14$' <<<"$verify_round"
grep -q '^substrate_weight_count=9$' <<<"$verify_round"
grep -q "^round_receipt_sha256=$round_receipt_sha$" <<<"$verify_round"
grep -q '^no_model_run=true$' <<<"$verify_round"
grep -q '^no_scorer_run=true$' <<<"$verify_round"

tampered_metric_receipt="$tmp/tampered-metric-receipt.json"
python3 - "$round_receipt" "$tampered_metric_receipt" <<'PYTAMPEREDMETRICRECEIPT'
import json
import sys

source, out = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    data = json.load(handle)
data["elevation_vs_frontier_solve_rate"] = 1.0
data["round_receipt_path"] = out
with open(out, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYTAMPEREDMETRICRECEIPT
if "$ROUND" --verify-round-receipt "$tampered_metric_receipt" >"$tmp/tampered-metric-verify.out" 2>"$tmp/tampered-metric-verify.err"; then
  echo "expected round receipt with stale materialized solve-rate delta to fail verification" >&2
  exit 1
fi
grep -q '^round_receipt_ok=false$' "$tmp/tampered-metric-verify.out"
grep -q '^round_receipt_schema_ok=false$' "$tmp/tampered-metric-verify.out"

tampered_student_model_receipt="$tmp/tampered-student-model-receipt.json"
python3 - "$round_receipt" "$tampered_student_model_receipt" <<'PYTAMPEREDSTUDENTMODELRECEIPT'
import json
import sys

source, out = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    data = json.load(handle)
data["student_model"] = "not-deepseek-v4-pro"
data["round_receipt_path"] = out
with open(out, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYTAMPEREDSTUDENTMODELRECEIPT
if "$ROUND" --verify-round-receipt "$tampered_student_model_receipt" >"$tmp/tampered-student-model-verify.out" 2>"$tmp/tampered-student-model-verify.err"; then
  echo "expected round receipt with stale materialized student model to fail verification" >&2
  exit 1
fi
grep -q '^round_receipt_ok=false$' "$tmp/tampered-student-model-verify.out"
grep -q '^round_receipt_schema_ok=false$' "$tmp/tampered-student-model-verify.out"

tampered_frontier_model_receipt="$tmp/tampered-frontier-model-receipt.json"
python3 - "$round_receipt" "$tampered_frontier_model_receipt" <<'PYTAMPEREDFRONTIERMODELRECEIPT'
import json
import sys

source, out = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    data = json.load(handle)
data["frontier_model"] = "not-frontier"
data["round_receipt_path"] = out
with open(out, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYTAMPEREDFRONTIERMODELRECEIPT
if "$ROUND" --verify-round-receipt "$tampered_frontier_model_receipt" >"$tmp/tampered-frontier-model-verify.out" 2>"$tmp/tampered-frontier-model-verify.err"; then
  echo "expected round receipt with stale materialized frontier model to fail verification" >&2
  exit 1
fi
grep -q '^round_receipt_ok=false$' "$tmp/tampered-frontier-model-verify.out"
grep -q '^round_receipt_schema_ok=false$' "$tmp/tampered-frontier-model-verify.out"

stale_round_path_receipt="$tmp/stale-round-path-receipt.json"
python3 - "$round_receipt" "$stale_round_path_receipt" <<'PYSTALEROUNDPATH'
import json
import sys

source, out = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    data = json.load(handle)
data["round_receipt_path"] = out + ".stale"
with open(out, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYSTALEROUNDPATH
if "$ROUND" --verify-round-receipt "$stale_round_path_receipt" >"$tmp/stale-round-path-verify.out" 2>"$tmp/stale-round-path-verify.err"; then
  echo "expected round receipt with stale embedded round_receipt_path to fail verification" >&2
  exit 1
fi
grep -q '^round_receipt_ok=false$' "$tmp/stale-round-path-verify.out"
grep -q '^round_receipt_schema_ok=false$' "$tmp/stale-round-path-verify.out"

tampered_selection_receipt="$tmp/tampered-selection-receipt.json"
python3 - "$round_receipt" "$tampered_selection_receipt" <<'PYTAMPEREDSELECTIONRECEIPT'
import json
import sys

source, out = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    data = json.load(handle)
data["selection_receipt_ok"] = False
data["round_receipt_path"] = out
with open(out, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYTAMPEREDSELECTIONRECEIPT
if "$ROUND" --verify-round-receipt "$tampered_selection_receipt" >"$tmp/tampered-selection-verify.out" 2>"$tmp/tampered-selection-verify.err"; then
  echo "expected round receipt with tampered selection proof to fail verification" >&2
  exit 1
fi
grep -q '^round_receipt_ok=false$' "$tmp/tampered-selection-verify.out"
grep -q '^round_receipt_schema_ok=false$' "$tmp/tampered-selection-verify.out"

not_ready_preflight="$tmp/not-ready-preflight.json"
python3 - "$outroot/round-contract/preflight.json" "$not_ready_preflight" <<'PYNOTREADYPREFLIGHT'
import json
import sys

source, out = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    data = json.load(handle)
data["ready_to_run"] = False
with open(out, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYNOTREADYPREFLIGHT
not_ready_preflight_sha="$(shasum -a 256 "$not_ready_preflight" | awk '{print $1}')"
not_ready_preflight_receipt="$tmp/not-ready-preflight-round-receipt.json"
python3 - "$round_receipt" "$not_ready_preflight_receipt" "$not_ready_preflight" "$not_ready_preflight_sha" <<'PYNOTREADYRECEIPT'
import json
import sys

source, out, preflight_path, preflight_sha = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    data = json.load(handle)
data["preflight_receipt_path"] = preflight_path
data["preflight_receipt_sha256"] = preflight_sha
with open(out, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYNOTREADYRECEIPT
if "$ROUND" --verify-round-receipt "$not_ready_preflight_receipt" >"$tmp/not-ready-preflight-round-verify.out" 2>"$tmp/not-ready-preflight-round-verify.err"; then
  echo "expected round receipt with hash-matching non-ready preflight to fail verification" >&2
  exit 1
fi
grep -q '^round_receipt_ok=false$' "$tmp/not-ready-preflight-round-verify.out"
grep -q '^round_receipt_schema_ok=false$' "$tmp/not-ready-preflight-round-verify.out"

bad_deepseek_api_preflight="$tmp/bad-deepseek-api-preflight.json"
python3 - "$outroot/round-contract/preflight.json" "$bad_deepseek_api_preflight" <<'PYBADDEEPSEEKAPIPREFLIGHT'
import json
import sys

source, out = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    data = json.load(handle)
data["deepseek_api_preflight_ok"] = False
with open(out, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYBADDEEPSEEKAPIPREFLIGHT
bad_deepseek_api_preflight_sha="$(shasum -a 256 "$bad_deepseek_api_preflight" | awk '{print $1}')"
bad_deepseek_api_preflight_receipt="$tmp/bad-deepseek-api-preflight-round-receipt.json"
python3 - "$round_receipt" "$bad_deepseek_api_preflight_receipt" "$bad_deepseek_api_preflight" "$bad_deepseek_api_preflight_sha" <<'PYBADDEEPSEEKAPIRECEIPT'
import json
import sys

source, out, preflight_path, preflight_sha = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    data = json.load(handle)
data["preflight_receipt_path"] = preflight_path
data["preflight_receipt_sha256"] = preflight_sha
with open(out, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYBADDEEPSEEKAPIRECEIPT
if "$ROUND" --verify-round-receipt "$bad_deepseek_api_preflight_receipt" >"$tmp/bad-deepseek-api-preflight-round-verify.out" 2>"$tmp/bad-deepseek-api-preflight-round-verify.err"; then
  echo "expected round receipt with hash-matching failed DeepSeek API preflight to fail verification" >&2
  exit 1
fi
grep -q '^round_receipt_ok=false$' "$tmp/bad-deepseek-api-preflight-round-verify.out"
grep -q '^round_receipt_schema_ok=false$' "$tmp/bad-deepseek-api-preflight-round-verify.out"

bad_modal_preflight="$tmp/bad-modal-preflight.json"
python3 - "$outroot/round-contract/preflight.json" "$bad_modal_preflight" <<'PYBADMODALPREFLIGHT'
import json
import sys

source, out = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    data = json.load(handle)
data["modal_preflight_ok"] = False
with open(out, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYBADMODALPREFLIGHT
bad_modal_preflight_sha="$(shasum -a 256 "$bad_modal_preflight" | awk '{print $1}')"
bad_modal_preflight_receipt="$tmp/bad-modal-preflight-round-receipt.json"
python3 - "$round_receipt" "$bad_modal_preflight_receipt" "$bad_modal_preflight" "$bad_modal_preflight_sha" <<'PYBADMODALRECEIPT'
import json
import sys

source, out, preflight_path, preflight_sha = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    data = json.load(handle)
data["preflight_receipt_path"] = preflight_path
data["preflight_receipt_sha256"] = preflight_sha
with open(out, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYBADMODALRECEIPT
if "$ROUND" --verify-round-receipt "$bad_modal_preflight_receipt" >"$tmp/bad-modal-preflight-round-verify.out" 2>"$tmp/bad-modal-preflight-round-verify.err"; then
  echo "expected round receipt with hash-matching failed Modal preflight to fail verification" >&2
  exit 1
fi
grep -q '^round_receipt_ok=false$' "$tmp/bad-modal-preflight-round-verify.out"
grep -q '^round_receipt_schema_ok=false$' "$tmp/bad-modal-preflight-round-verify.out"

bad_rotation_preflight="$tmp/bad-rotation-attestation-preflight.json"
python3 - "$outroot/round-contract/preflight.json" "$bad_rotation_preflight" <<'PYBADROTATIONPREFLIGHT'
import json
import sys

source, out = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    data = json.load(handle)
data["credential_rotation_attestation_ok"] = False
with open(out, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYBADROTATIONPREFLIGHT
bad_rotation_preflight_sha="$(shasum -a 256 "$bad_rotation_preflight" | awk '{print $1}')"
bad_rotation_preflight_receipt="$tmp/bad-rotation-attestation-round-receipt.json"
python3 - "$round_receipt" "$bad_rotation_preflight_receipt" "$bad_rotation_preflight" "$bad_rotation_preflight_sha" <<'PYBADROTATIONRECEIPT'
import json
import sys

source, out, preflight_path, preflight_sha = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    data = json.load(handle)
data["preflight_receipt_path"] = preflight_path
data["preflight_receipt_sha256"] = preflight_sha
with open(out, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYBADROTATIONRECEIPT
if "$ROUND" --verify-round-receipt "$bad_rotation_preflight_receipt" >"$tmp/bad-rotation-attestation-round-verify.out" 2>"$tmp/bad-rotation-attestation-round-verify.err"; then
  echo "expected round receipt with hash-matching missing credential-rotation attestation to fail verification" >&2
  exit 1
fi
grep -q '^round_receipt_ok=false$' "$tmp/bad-rotation-attestation-round-verify.out"
grep -q '^round_receipt_schema_ok=false$' "$tmp/bad-rotation-attestation-round-verify.out"

missing_selection_summary="$tmp/missing-selection-elevation-summary.json"
printf '{"metric":"elevation","metric_claim":false,"benchmark_suite":"swe_bench_pro","benchmark_dataset_name":"ScaleAI/SWE-bench_Pro","official_benchmark":true,"task_ids":["pro__task-a","pro__task-b"],"task_count":2,"selected_task_ids_sha256":"%s","frontier_baseline_path":"%s","frontier_baseline_sha256":"%s","frontier_baseline_resolved":1,"frontier_solve_rate":0.5,"deepseek_control_resolved":0,"deepseek_control_solve_rate":0.0,"atomic_substrate_resolved":1,"student_solve_rate":0.5,"elevation_vs_frontier":0,"elevation_vs_frontier_solve_rate":0.0,"elevation_vs_deepseek_control":1,"elevation_vs_deepseek_control_solve_rate":0.5,"student_model":"deepseek-v4-pro","elevation_valid":true,"task_provenance_ok":true,"suite_preflight_ok":true,"frontier_baseline_evidence_receipt_ok":true,"frontier_baseline_provenance_ok":true,"teacher_atomic":true,"anti_replay":true,"distinct_tasks":true,"sample_timeouts":0,"score_failures":0,"reused_samples":0,"rerun_timeout_samples":0}\n' "$task_ids_sha" "$outroot/round-contract/frontier_baseline.json" "$baseline_sha" >"$missing_selection_summary"
missing_selection_summary_sha="$(shasum -a 256 "$missing_selection_summary" | awk '{print $1}')"
missing_selection_receipt="$tmp/missing-selection-elevation-receipt.json"
python3 - "$round_receipt" "$missing_selection_receipt" "$missing_selection_summary" "$missing_selection_summary_sha" <<'PYMISSINGSELECTION'
import json
import sys

source, out, summary_path, summary_sha = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    data = json.load(handle)
data["elevation_summary_path"] = summary_path
data["elevation_summary_sha256"] = summary_sha
data["round_receipt_path"] = out
with open(out, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYMISSINGSELECTION
if "$ROUND" --verify-round-receipt "$missing_selection_receipt" >"$tmp/missing-selection-verify.out" 2>"$tmp/missing-selection-verify.err"; then
  echo "expected round receipt with hash-matching elevation summary missing selection proof to fail verification" >&2
  exit 1
fi
grep -q '^round_receipt_ok=false$' "$tmp/missing-selection-verify.out"
grep -q '^round_receipt_schema_ok=false$' "$tmp/missing-selection-verify.out"

bad_elevation_summary="$tmp/bad-elevation-summary.json"
printf '{"metric":"elevation","metric_claim":false,"benchmark_suite":"swe_bench_pro","benchmark_dataset_name":"ScaleAI/SWE-bench_Pro","official_benchmark":true,"task_ids":["pro__task-a","pro__task-b"],"elevation_valid":true,"task_provenance_ok":true,"suite_preflight_ok":true,"frontier_baseline_evidence_receipt_ok":true,"frontier_baseline_provenance_ok":true,"teacher_atomic":true,"anti_replay":true,"distinct_tasks":true}\n' >"$bad_elevation_summary"
bad_elevation_summary_sha="$(shasum -a 256 "$bad_elevation_summary" | awk '{print $1}')"
bad_elevation_receipt="$tmp/bad-elevation-summary-receipt.json"
python3 - "$round_receipt" "$bad_elevation_receipt" "$bad_elevation_summary" "$bad_elevation_summary_sha" <<'PYBADSUMMARY'
import json
import sys

source, out, summary_path, summary_sha = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    data = json.load(handle)
data["elevation_summary_path"] = summary_path
data["elevation_summary_sha256"] = summary_sha
with open(out, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYBADSUMMARY
if "$ROUND" --verify-round-receipt "$bad_elevation_receipt" >"$tmp/bad-elevation-summary-verify.out" 2>"$tmp/bad-elevation-summary-verify.err"; then
  echo "expected round receipt with malformed but hash-matching elevation summary to fail verification" >&2
  exit 1
fi
grep -q '^round_receipt_ok=false$' "$tmp/bad-elevation-summary-verify.out"
grep -q '^round_receipt_schema_ok=false$' "$tmp/bad-elevation-summary-verify.out"

hidden_failure_summary="$tmp/hidden-failure-elevation-summary.json"
printf '{"metric":"elevation","metric_claim":false,"benchmark_suite":"swe_bench_pro","benchmark_dataset_name":"ScaleAI/SWE-bench_Pro","official_benchmark":true,"task_ids":["pro__task-a","pro__task-b"],"selected_task_ids_sha256":"%s","frontier_baseline_path":"%s","frontier_baseline_sha256":"%s","elevation_valid":true,"task_provenance_ok":true,"suite_preflight_ok":true,"frontier_baseline_evidence_receipt_ok":true,"frontier_baseline_provenance_ok":true,"teacher_atomic":true,"anti_replay":true,"distinct_tasks":true,"sample_timeouts":0,"score_failures":1,"reused_samples":0,"rerun_timeout_samples":0}\n' "$task_ids_sha" "$outroot/round-contract/frontier_baseline.json" "$baseline_sha" >"$hidden_failure_summary"
hidden_failure_summary_sha="$(shasum -a 256 "$hidden_failure_summary" | awk '{print $1}')"
hidden_failure_receipt="$tmp/hidden-failure-elevation-receipt.json"
python3 - "$round_receipt" "$hidden_failure_receipt" "$hidden_failure_summary" "$hidden_failure_summary_sha" <<'PYHIDDENFAILURE'
import json
import sys

source, out, summary_path, summary_sha = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    data = json.load(handle)
data["elevation_summary_path"] = summary_path
data["elevation_summary_sha256"] = summary_sha
with open(out, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYHIDDENFAILURE
if "$ROUND" --verify-round-receipt "$hidden_failure_receipt" >"$tmp/hidden-failure-verify.out" 2>"$tmp/hidden-failure-verify.err"; then
  echo "expected round receipt with nonzero elevation failure counters to fail verification" >&2
  exit 1
fi
grep -q '^round_receipt_ok=false$' "$tmp/hidden-failure-verify.out"
grep -q '^round_receipt_schema_ok=false$' "$tmp/hidden-failure-verify.out"

wrong_student_verified_summary="$tmp/wrong-student-verified-elevation-summary.json"
printf '{"metric":"elevation","metric_claim":false,"benchmark_suite":"swe_bench_pro","benchmark_dataset_name":"ScaleAI/SWE-bench_Pro","official_benchmark":true,"task_ids":["pro__task-a","pro__task-b"],"task_count":2,"selected_task_ids_sha256":"%s","frontier_baseline_path":"%s","frontier_baseline_sha256":"%s","frontier_baseline_resolved":1,"frontier_solve_rate":0.5,"deepseek_control_resolved":0,"deepseek_control_solve_rate":0.0,"atomic_substrate_resolved":1,"student_solve_rate":0.5,"elevation_vs_frontier":0,"elevation_vs_frontier_solve_rate":0.0,"elevation_vs_deepseek_control":1,"elevation_vs_deepseek_control_solve_rate":0.5,"student_model":"not-deepseek-v4-pro","elevation_valid":true,"task_provenance_ok":true,"suite_preflight_ok":true,"frontier_baseline_evidence_receipt_ok":true,"frontier_baseline_provenance_ok":true,"teacher_atomic":true,"anti_replay":true,"distinct_tasks":true,"sample_timeouts":0,"score_failures":0,"reused_samples":0,"rerun_timeout_samples":0}\n' "$task_ids_sha" "$outroot/round-contract/frontier_baseline.json" "$baseline_sha" >"$wrong_student_verified_summary"
wrong_student_verified_summary_sha="$(shasum -a 256 "$wrong_student_verified_summary" | awk '{print $1}')"
wrong_student_verified_receipt="$tmp/wrong-student-verified-receipt.json"
python3 - "$round_receipt" "$wrong_student_verified_receipt" "$wrong_student_verified_summary" "$wrong_student_verified_summary_sha" <<'PYWRONGSTUDENTVERIFY'
import json
import sys

source, out, summary_path, summary_sha = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    data = json.load(handle)
data["elevation_summary_path"] = summary_path
data["elevation_summary_sha256"] = summary_sha
data["round_receipt_path"] = out
with open(out, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYWRONGSTUDENTVERIFY
if "$ROUND" --verify-round-receipt "$wrong_student_verified_receipt" >"$tmp/wrong-student-verified-verify.out" 2>"$tmp/wrong-student-verified-verify.err"; then
  echo "expected round receipt with non-DeepSeek student model to fail verification" >&2
  exit 1
fi
grep -q '^round_receipt_ok=false$' "$tmp/wrong-student-verified-verify.out"
grep -q '^round_receipt_schema_ok=false$' "$tmp/wrong-student-verified-verify.out"

claimful_elevation_summary="$tmp/claimful-elevation-summary.json"
printf '{"metric":"elevation","metric_claim":true,"benchmark_suite":"swe_bench_pro","benchmark_dataset_name":"ScaleAI/SWE-bench_Pro","official_benchmark":true,"task_ids":["pro__task-a","pro__task-b"],"selected_task_ids_sha256":"%s","frontier_baseline_path":"%s","frontier_baseline_sha256":"%s","elevation_valid":true,"task_provenance_ok":true,"suite_preflight_ok":true,"frontier_baseline_evidence_receipt_ok":true,"frontier_baseline_provenance_ok":true,"teacher_atomic":true,"anti_replay":true,"distinct_tasks":true,"sample_timeouts":0,"score_failures":0,"reused_samples":0,"rerun_timeout_samples":0}\n' "$task_ids_sha" "$outroot/round-contract/frontier_baseline.json" "$baseline_sha" >"$claimful_elevation_summary"
claimful_elevation_summary_sha="$(shasum -a 256 "$claimful_elevation_summary" | awk '{print $1}')"
claimful_elevation_receipt="$tmp/claimful-elevation-receipt.json"
python3 - "$round_receipt" "$claimful_elevation_receipt" "$claimful_elevation_summary" "$claimful_elevation_summary_sha" <<'PYCLAIMFULSUMMARY'
import json
import sys

source, out, summary_path, summary_sha = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    data = json.load(handle)
data["elevation_summary_path"] = summary_path
data["elevation_summary_sha256"] = summary_sha
with open(out, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYCLAIMFULSUMMARY
if "$ROUND" --verify-round-receipt "$claimful_elevation_receipt" >"$tmp/claimful-elevation-verify.out" 2>"$tmp/claimful-elevation-verify.err"; then
  echo "expected round receipt with claimful elevation summary to fail verification" >&2
  exit 1
fi
grep -q '^round_receipt_ok=false$' "$tmp/claimful-elevation-verify.out"
grep -q '^round_receipt_schema_ok=false$' "$tmp/claimful-elevation-verify.out"

stale_frontier_summary="$tmp/stale-frontier-summary.json"
python3 - "$frontier_summary" "$stale_frontier_summary" <<'PYSTALEFRONTIERSUMMARY'
import json
import sys

source, out = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    data = json.load(handle)
data["frontier_baseline_sha256"] = "0" * 64
with open(out, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYSTALEFRONTIERSUMMARY
stale_frontier_summary_sha="$(shasum -a 256 "$stale_frontier_summary" | awk '{print $1}')"
stale_frontier_summary_receipt="$tmp/stale-frontier-summary-receipt.json"
python3 - "$round_receipt" "$stale_frontier_summary_receipt" "$stale_frontier_summary" "$stale_frontier_summary_sha" <<'PYSTALEFRONTIERRECEIPT'
import json
import sys

source, out, summary_path, summary_sha = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    data = json.load(handle)
data["frontier_baseline_summary_path"] = summary_path
data["frontier_baseline_summary_sha256"] = summary_sha
data["round_receipt_path"] = out
with open(out, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYSTALEFRONTIERRECEIPT
if "$ROUND" --verify-round-receipt "$stale_frontier_summary_receipt" >"$tmp/stale-frontier-summary-verify.out" 2>"$tmp/stale-frontier-summary-verify.err"; then
  echo "expected round receipt with stale frontier baseline summary hash binding to fail verification" >&2
  exit 1
fi
grep -q '^round_receipt_ok=false$' "$tmp/stale-frontier-summary-verify.out"
grep -q '^round_receipt_schema_ok=false$' "$tmp/stale-frontier-summary-verify.out"
grep -q '^frontier_summary_verification_ok=false$' "$tmp/stale-frontier-summary-verify.out"

tampered_round_provenance_receipt="$tmp/tampered-round-provenance-receipt.json"
sed 's/"task_provenance_sha256": "[^"]*"/"task_provenance_sha256": "stale"/' "$round_receipt" >"$tampered_round_provenance_receipt"
if "$ROUND" --verify-round-receipt "$tampered_round_provenance_receipt" >"$tmp/tampered-round-provenance-verify.out" 2>"$tmp/tampered-round-provenance-verify.err"; then
  echo "expected tampered round task provenance hash to fail verification" >&2
  exit 1
fi
grep -q '^round_receipt_ok=false$' "$tmp/tampered-round-provenance-verify.out"
grep -q '^round_receipt_schema_ok=false$' "$tmp/tampered-round-provenance-verify.out"

tampered_round_summary_receipt="$tmp/tampered-round-summary-receipt.json"
sed 's/"frontier_baseline_summary_sha256": "[^"]*"/"frontier_baseline_summary_sha256": "stale"/' "$round_receipt" >"$tampered_round_summary_receipt"
if "$ROUND" --verify-round-receipt "$tampered_round_summary_receipt" >"$tmp/tampered-round-summary-verify.out" 2>"$tmp/tampered-round-summary-verify.err"; then
  echo "expected tampered frontier baseline summary hash to fail verification" >&2
  exit 1
fi
grep -q '^round_receipt_ok=false$' "$tmp/tampered-round-summary-verify.out"
grep -q '^round_receipt_artifact_hashes_ok=false$' "$tmp/tampered-round-summary-verify.out"

tampered_round_receipt="$tmp/tampered-round-receipt.json"
sed 's/"weights_sha256": "[^"]*"/"weights_sha256": "stale"/' "$round_receipt" >"$tampered_round_receipt"
if "$ROUND" --verify-round-receipt "$tampered_round_receipt" >"$tmp/tampered-round-verify.out" 2>"$tmp/tampered-round-verify.err"; then
  echo "expected tampered round receipt to fail verification" >&2
  exit 1
fi
grep -q '^round_receipt_ok=false$' "$tmp/tampered-round-verify.out"
grep -q '^round_receipt_artifact_hashes_ok=false$' "$tmp/tampered-round-verify.out"

if "$ROUND" --verify-round-receipt "$tmp/missing-round-receipt.json" >"$tmp/missing-round-verify.out" 2>"$tmp/missing-round-verify.err"; then
  echo "expected missing round receipt to fail verification" >&2
  exit 1
fi
grep -q '^round_receipt_exists=false$' "$tmp/missing-round-verify.out"
grep -q '^round_receipt_ok=false$' "$tmp/missing-round-verify.out"
grep -q '^no_model_run=true$' "$tmp/missing-round-verify.out"
grep -q '^no_scorer_run=true$' "$tmp/missing-round-verify.out"
grep -q '"ready_to_run": true' "$outroot/round-contract/preflight.json"
grep -q '"credential_rotation_attestation_ok": true' "$outroot/round-contract/preflight.json"
grep -q '"production_ready_to_run": false' "$outroot/round-contract/preflight.json"
grep -q '"no_model_run": true' "$outroot/round-contract/preflight.json"
grep -q '"no_scorer_run": true' "$outroot/round-contract/preflight.json"

test -x "$ROUND"
grep -q 'run_frontier_baseline.sh' "$ROUND"
grep -q 'run_elevation_stream.sh' "$ROUND"
grep -q 'DEEPSEEK_API_KEY' "$ROUND"
grep -q 'elevation_pro_suite_manifest.json' "$ROUND"
if grep -q '/tmp/.atomic_creds.sh' "$ROUND"; then
  echo "Pro round runner must not source credential files; use env only" >&2
  exit 1
fi

echo "Pro elevation round runner contract ok"
