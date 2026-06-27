#!/usr/bin/env bash
set -euo pipefail

HERE="/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"
cd "$HERE"

CURVE="$HERE/verify_pro_elevation_curve.sh"
ROUND="$HERE/run_pro_elevation_round.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/make_rounds.py" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
task_ids = [f"pro__task-{idx:02d}" for idx in range(100)]
task_ids_sha = hashlib.sha256("\n".join(task_ids).encode()).hexdigest()
provenance_sha = "a" * 64


def write(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(payload, str):
        path.write_text(payload, encoding="utf-8")
    else:
        path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def make_round(name, accumulation_index, student_resolved, admissible=True):
    d = root / name
    d.mkdir(parents=True, exist_ok=True)
    frontier_resolved = 50
    control_resolved = 30
    task_count = len(task_ids)
    frontier_rate = frontier_resolved / task_count
    student_rate = student_resolved / task_count
    control_rate = control_resolved / task_count
    delta_frontier_rate = round(student_rate - frontier_rate, 12)
    delta_control_rate = round(student_rate - control_rate, 12)

    manifest = d / "manifest.json"
    write(manifest, {"selected_task_ids": task_ids, "metric_claim": False})
    manifest_sha = sha(manifest)
    frontier_runner = d / "frontier_runner.sh"
    elevation_stream = d / "elevation_stream.sh"
    weights = d / "weights.jsonl"
    write(frontier_runner, """#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--verify-summary" ]; then
  summary="${2:-}"
  python3 - "$summary" <<'PYVERIFYFRONTIER'
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
PYVERIFYFRONTIER
  exit $?
fi
exit 0
""")
    frontier_runner.chmod(0o755)
    write(elevation_stream, "#!/usr/bin/env bash\nexit 0\n")
    write(weights, '{"act":{"preconditions":[],"transformation":[],"effects":[],"cost":0,"receipt":{},"fidelity_battery":[]}}\n')
    baseline = d / "frontier_baseline.json"
    write(baseline, {"frontier_baseline": True})
    baseline_sha = sha(baseline)

    frontier_summary = d / "frontier_baseline_summary.json"
    write(frontier_summary, {
        "metric": "frontier_baseline_receipt",
        "metric_claim": False,
        "benchmark_suite": "swe_bench_pro",
        "benchmark_dataset_name": "ScaleAI/SWE-bench_Pro",
        "benchmark_label": "SWE-bench-Pro",
        "official_benchmark": True,
        "baseline_role": "frontier",
        "frozen": True,
        "official_docker": True,
        "frontier_model": "fake-frontier",
        "task_ids": task_ids,
        "task_ids_sha256": task_ids_sha,
        "task_provenance_ok": True,
        "task_provenance_sha256": provenance_sha,
        "suite_preflight_ok": True,
        "frontier_baseline_path": str(baseline),
        "frontier_baseline_sha256": baseline_sha,
        "frontier_baseline_evidence_receipt_ok": True,
        "sample_failures": 0,
        "score_failures": 0,
    })

    preflight_production = bool(admissible)
    preflight = d / "preflight.json"
    write(preflight, {
        "metric": "pro_elevation_preflight",
        "metric_claim": False,
        "benchmark_suite": "swe_bench_pro",
        "benchmark_dataset_name": "ScaleAI/SWE-bench_Pro",
        "official_benchmark": True,
        "manifest_path": str(manifest),
        "selected_task_count": task_count,
        "selected_task_ids_sha256": task_ids_sha,
        "selection_manifest_path": str(manifest),
        "selection_manifest_sha256": manifest_sha,
        "selection_receipt_ok": True,
        "anti_cherry_pick": True,
        "deepseek_api_key_present": True,
        "modal_token_id_present": True,
        "modal_token_secret_present": True,
        "modal_credentials_present": True,
        "deepseek_api_key_format_ok": True,
        "modal_token_id_format_ok": True,
        "modal_token_secret_format_ok": True,
        "modal_credentials_format_ok": True,
        "credential_format_bypassed_by_test_runner": False,
        "credential_format_ok": True,
        "production_credential_format_ok": True,
        "credential_rotation_attested": True,
        "credential_rotation_attestation_bypassed_by_test_runner": False,
        "credential_rotation_attestation_ok": True,
        "deepseek_auth_ok": True,
        "deepseek_balance_available": True,
        "official_deepseek_api_preflight_ok": True,
        "deepseek_api_preflight_bypassed_by_test_runner": False,
        "deepseek_api_preflight_ok": True,
        "modal_cli_present": True,
        "modal_auth_ok": True,
        "official_modal_preflight_ok": True,
        "modal_preflight_bypassed_by_test_runner": False,
        "modal_preflight_ok": True,
        "credential_source": "env",
        "credential_file_allowed": False,
        "runner_policy_ok": True,
        "canonical_toolchain": True,
        "test_runner_override_allowed": False,
        "swebench_import_ok": True,
        "docker_api_ok": True,
        "official_scorer_preflight_ok": True,
        "scorer_preflight_ok": True,
        "scorer_preflight_bypassed_by_test_runner": False,
        "frontier_runner_ok": True,
        "frontier_baseline_runner": str(frontier_runner),
        "frontier_baseline_runner_sha256": sha(frontier_runner),
        "elevation_stream_ok": True,
        "elevation_stream": str(elevation_stream),
        "elevation_stream_sha256": sha(elevation_stream),
        "weights_ok": True,
        "task_layout_ok": True,
        "task_provenance_ok": True,
        "task_provenance_sha256": provenance_sha,
        "suite_pristine_layout_ok": True,
        "ready_to_run": True,
        "production_ready_to_run": preflight_production,
        "no_model_run": True,
        "no_scorer_run": True,
    })

    elevation_summary = d / "elevation_summary.json"
    write(elevation_summary, {
        "metric": "elevation",
        "metric_claim": False,
        "benchmark_suite": "swe_bench_pro",
        "benchmark_dataset_name": "ScaleAI/SWE-bench_Pro",
        "official_benchmark": True,
        "metric_scope": "paired_frontier_solve_rate_delta",
        "within_task_efficiency_metric_admissible": False,
        "task_ids": task_ids,
        "task_count": task_count,
        "selected_task_ids_sha256": task_ids_sha,
        "selection_manifest_path": str(manifest),
        "selection_manifest_sha256": manifest_sha,
        "selection_receipt_ok": True,
        "anti_cherry_pick": True,
        "frontier_baseline_path": str(baseline),
        "frontier_baseline_sha256": baseline_sha,
        "frontier_baseline_role": "frontier",
        "frontier_baseline_frozen": True,
        "frontier_baseline_official_docker": True,
        "frontier_baseline_benchmark_label": "SWE-bench-Pro",
        "frontier_baseline_resolved": frontier_resolved,
        "frontier_solve_rate": frontier_rate,
        "deepseek_control_resolved": control_resolved,
        "deepseek_control_solve_rate": control_rate,
        "atomic_substrate_resolved": student_resolved,
        "student_solve_rate": student_rate,
        "elevation_vs_frontier": student_resolved - frontier_resolved,
        "elevation_vs_frontier_solve_rate": delta_frontier_rate,
        "elevation_vs_deepseek_control": student_resolved - control_resolved,
        "elevation_vs_deepseek_control_solve_rate": delta_control_rate,
        "accumulation_index": accumulation_index,
        "substrate_weight_count": 9 + accumulation_index,
        "student_model": "deepseek-v4-pro",
        "elevation_valid": True,
        "task_provenance_ok": True,
        "suite_preflight_ok": True,
        "frontier_baseline_evidence_receipt_ok": True,
        "frontier_baseline_provenance_ok": True,
        "teacher_atomic": True,
        "anti_replay": True,
        "distinct_tasks": True,
        "sample_timeouts": 0,
        "score_failures": 0,
        "reused_samples": 0,
        "rerun_timeout_samples": 0,
    })

    receipt = d / "round_receipt.json"
    payload = {
        "metric": "pro_elevation_round",
        "metric_claim": False,
        "production_ready_to_run": preflight_production,
        "metric_admissible": preflight_production,
        "production_toolchain_ok": preflight_production,
        "run_id": name,
        "benchmark_suite": "swe_bench_pro",
        "benchmark_dataset_name": "ScaleAI/SWE-bench_Pro",
        "official_benchmark": True,
        "metric_scope": "paired_frontier_solve_rate_delta",
        "within_task_efficiency_metric_admissible": False,
        "manifest_path": str(manifest),
        "selected_task_count": task_count,
        "selected_task_ids_sha256": task_ids_sha,
        "selection_manifest_path": str(manifest),
        "selection_manifest_sha256": manifest_sha,
        "selection_receipt_ok": True,
        "anti_cherry_pick": True,
        "frontier_baseline_runner": str(frontier_runner),
        "frontier_baseline_runner_sha256": sha(frontier_runner),
        "elevation_stream": str(elevation_stream),
        "elevation_stream_sha256": sha(elevation_stream),
        "weights_path": str(weights),
        "weights_sha256": sha(weights),
        "preflight_receipt_path": str(preflight),
        "preflight_receipt_sha256": sha(preflight),
        "preflight_verification_ok": True,
        "task_provenance_ok": True,
        "task_provenance_sha256": provenance_sha,
        "frontier_baseline_path": str(baseline),
        "frontier_baseline_sha256": baseline_sha,
        "frontier_model": "fake-frontier",
        "frontier_baseline_role": "frontier",
        "frontier_baseline_frozen": True,
        "frontier_baseline_official_docker": True,
        "frontier_baseline_benchmark_label": "SWE-bench-Pro",
        "frontier_baseline_summary_path": str(frontier_summary),
        "frontier_baseline_summary_sha256": sha(frontier_summary),
        "frontier_summary_verification_ok": True,
        "frontier_baseline_evidence_receipt_ok": True,
        "frontier_baseline_resolved": frontier_resolved,
        "frontier_solve_rate": frontier_rate,
        "deepseek_control_resolved": control_resolved,
        "deepseek_control_solve_rate": control_rate,
        "atomic_substrate_resolved": student_resolved,
        "student_solve_rate": student_rate,
        "student_model": "deepseek-v4-pro",
        "elevation_vs_frontier": student_resolved - frontier_resolved,
        "elevation_vs_frontier_solve_rate": delta_frontier_rate,
        "elevation_vs_deepseek_control": student_resolved - control_resolved,
        "elevation_vs_deepseek_control_solve_rate": delta_control_rate,
        "accumulation_index": accumulation_index,
        "substrate_weight_count": 9 + accumulation_index,
        "elevation_valid_if_run": True,
        "elevation_summary_path": str(elevation_summary),
        "elevation_summary_sha256": sha(elevation_summary),
        "round_receipt_path": str(receipt),
        "task_ids": task_ids,
    }
    write(receipt, payload)
    return str(receipt)


paths = {
    "r1": make_round("r1", 1, 40, True),
    "r2": make_round("r2", 2, 50, True),
    "r3": make_round("r3", 3, 70, True),
    "flat1": make_round("flat1", 1, 60, True),
    "flat2": make_round("flat2", 2, 55, True),
    "nonadmissible": make_round("nonadmissible", 4, 80, False),
}
for key, value in paths.items():
    print(f"{key}={value}")
PY

eval "$(python3 "$tmp/make_rounds.py" "$tmp/rounds")"
round_verifier_sha="$(shasum -a 256 "$ROUND" | awk '{print $1}')"
curve_verifier_sha="$(shasum -a 256 "$CURVE" | awk '{print $1}')"

selftest="$("$CURVE" --selftest)"
grep -q '^metric=pro_elevation_delta_curve_verifier$' <<<"$selftest"
grep -q '^metric_claim=false$' <<<"$selftest"
grep -q '^requires_round_receipt_ok=true$' <<<"$selftest"
grep -q '^requires_metric_admissible=true$' <<<"$selftest"
grep -q '^requires_frontier_summary_verification_ok=true$' <<<"$selftest"
grep -q '^requires_round_verifications=true$' <<<"$selftest"
grep -q '^requires_current_replay=true$' <<<"$selftest"
grep -q "^curve_verifier_path=$CURVE$" <<<"$selftest"
grep -q "^curve_verifier_sha256=$curve_verifier_sha$" <<<"$selftest"
grep -q "^round_verifier_path=$ROUND$" <<<"$selftest"
grep -q "^round_verifier_sha256=$round_verifier_sha$" <<<"$selftest"
grep -q '^curve_axis=accumulation_index$' <<<"$selftest"
grep -q '^curve_y=elevation_vs_frontier_solve_rate$' <<<"$selftest"
grep -q 'summary_fields=.*all_frontier_summaries_verified' <<<"$selftest"
grep -q 'summary_fields=.*curve_verifier_path' <<<"$selftest"
grep -q 'summary_fields=.*curve_verifier_sha256' <<<"$selftest"
grep -q 'summary_fields=.*curve_verifier_identity_ok' <<<"$selftest"
grep -q 'summary_fields=.*round_verifier_path' <<<"$selftest"
grep -q 'summary_fields=.*round_verifier_sha256' <<<"$selftest"
grep -q 'summary_fields=.*round_verifier_identity_ok' <<<"$selftest"
grep -q 'summary_fields=.*stable_projection_matches_current' <<<"$selftest"
grep -q 'summary_fields=.*stable_projection_mismatch_count' <<<"$selftest"
grep -q 'summary_fields=.*stable_projection_mismatch_paths' <<<"$selftest"
grep -q 'summary_fields=.*schema_issue_count' <<<"$selftest"
grep -q 'summary_fields=.*schema_issue_paths' <<<"$selftest"
grep -q 'summary_fields=.*same_benchmark' <<<"$selftest"
grep -q 'summary_fields=.*same_metric_contract' <<<"$selftest"
grep -q 'summary_fields=.*rate_formulas_ok' <<<"$selftest"
grep -q 'summary_fields=.*margin_growing' <<<"$selftest"
grep -q 'summary_fields=.*round_verifications' <<<"$selftest"
grep -q '^no_model_run=true$' <<<"$selftest"
grep -q '^no_scorer_run=true$' <<<"$selftest"

"$ROUND" --verify-round-receipt "$r1" >/tmp/curve-round-r1.verify
grep -q '^round_receipt_ok=true$' /tmp/curve-round-r1.verify
grep -q '^metric_admissible=true$' /tmp/curve-round-r1.verify
grep -q '^frontier_summary_verification_ok=true$' /tmp/curve-round-r1.verify

if "$CURVE" --output "$tmp/missing.json" >"$tmp/missing.out" 2>"$tmp/missing.err"; then
  echo "expected missing curve inputs to fail" >&2
  exit 1
fi
grep -q '^curve_valid=false$' "$tmp/missing.out"
grep -q '^round_count=0$' "$tmp/missing.out"

curve_out="$("$CURVE" --output "$tmp/curve.json" "$r2" "$r1" "$r3")"
grep -q '^metric=pro_elevation_delta_curve$' <<<"$curve_out"
grep -q '^metric_claim=false$' <<<"$curve_out"
grep -q '^curve_valid=true$' <<<"$curve_out"
grep -q '^round_count=3$' <<<"$curve_out"
grep -q '^all_rounds_verified=true$' <<<"$curve_out"
grep -q '^all_rounds_metric_admissible=true$' <<<"$curve_out"
grep -q '^all_frontier_summaries_verified=true$' <<<"$curve_out"
grep -q '^same_task_vector=true$' <<<"$curve_out"
grep -q '^same_frontier_baseline=true$' <<<"$curve_out"
grep -q '^same_benchmark=true$' <<<"$curve_out"
grep -q '^same_metric_contract=true$' <<<"$curve_out"
grep -q '^rate_formulas_ok=true$' <<<"$curve_out"
grep -q '^strictly_increasing_accumulation=true$' <<<"$curve_out"
grep -q '^margin_growing=true$' <<<"$curve_out"
grep -q '^accumulation_indices=1,2,3$' <<<"$curve_out"
grep -q '^elevation_vs_frontier_solve_rates=-0.1,0,0.2$' <<<"$curve_out"
grep -q '^latest_elevation_vs_frontier_solve_rate=0.2$' <<<"$curve_out"
grep -q "^curve_verifier_path=$CURVE$" <<<"$curve_out"
grep -q "^curve_verifier_sha256=$curve_verifier_sha$" <<<"$curve_out"
grep -q "^round_verifier_path=$ROUND$" <<<"$curve_out"
grep -q "^round_verifier_sha256=$round_verifier_sha$" <<<"$curve_out"
grep -q "^curve_receipt_path=$tmp/curve.json$" <<<"$curve_out"
grep -q '^no_model_run=true$' <<<"$curve_out"
grep -q '^no_scorer_run=true$' <<<"$curve_out"
grep -q '"metric": "pro_elevation_delta_curve"' "$tmp/curve.json"
grep -q '"curve_valid": true' "$tmp/curve.json"
grep -q '"all_frontier_summaries_verified": true' "$tmp/curve.json"
grep -q '"frontier_summary_verification_ok": true' "$tmp/curve.json"
grep -q "\"curve_verifier_path\": \"$CURVE\"" "$tmp/curve.json"
grep -q "\"curve_verifier_sha256\": \"$curve_verifier_sha\"" "$tmp/curve.json"
grep -q "\"round_verifier_path\": \"$ROUND\"" "$tmp/curve.json"
grep -q "\"round_verifier_sha256\": \"$round_verifier_sha\"" "$tmp/curve.json"
grep -q '"margin_growing": true' "$tmp/curve.json"
grep -q '"accumulation_index": 1' "$tmp/curve.json"
grep -q '"accumulation_index": 3' "$tmp/curve.json"

verify_curve="$("$CURVE" --verify-curve-receipt "$tmp/curve.json")"
grep -q '^metric=pro_elevation_delta_curve_receipt_verification$' <<<"$verify_curve"
grep -q '^metric_claim=false$' <<<"$verify_curve"
grep -q "^curve_receipt_path=$tmp/curve.json$" <<<"$verify_curve"
grep -q '^curve_receipt_exists=true$' <<<"$verify_curve"
grep -q '^curve_receipt_schema_ok=true$' <<<"$verify_curve"
grep -q '^curve_receipt_matches_current=true$' <<<"$verify_curve"
grep -q '^curve_receipt_ok=true$' <<<"$verify_curve"
grep -q '^curve_valid=true$' <<<"$verify_curve"
grep -q '^round_count=3$' <<<"$verify_curve"
grep -q '^all_rounds_verified=true$' <<<"$verify_curve"
grep -q '^all_rounds_metric_admissible=true$' <<<"$verify_curve"
grep -q '^all_frontier_summaries_verified=true$' <<<"$verify_curve"
grep -q '^same_task_vector=true$' <<<"$verify_curve"
grep -q '^same_frontier_baseline=true$' <<<"$verify_curve"
grep -q '^same_benchmark=true$' <<<"$verify_curve"
grep -q '^same_metric_contract=true$' <<<"$verify_curve"
grep -q '^rate_formulas_ok=true$' <<<"$verify_curve"
grep -q '^strictly_increasing_accumulation=true$' <<<"$verify_curve"
grep -q '^margin_growing=true$' <<<"$verify_curve"
grep -q "^curve_verifier_path=$CURVE$" <<<"$verify_curve"
grep -q "^curve_verifier_sha256=$curve_verifier_sha$" <<<"$verify_curve"
grep -q '^curve_verifier_identity_ok=true$' <<<"$verify_curve"
grep -q "^round_verifier_path=$ROUND$" <<<"$verify_curve"
grep -q "^round_verifier_sha256=$round_verifier_sha$" <<<"$verify_curve"
grep -q '^round_verifier_identity_ok=true$' <<<"$verify_curve"
grep -q '^stable_projection_matches_current=true$' <<<"$verify_curve"
grep -q '^stable_projection_mismatch_count=0$' <<<"$verify_curve"
grep -q '^stable_projection_mismatch_paths=$' <<<"$verify_curve"
grep -q '^schema_issue_count=0$' <<<"$verify_curve"
grep -q '^schema_issue_paths=$' <<<"$verify_curve"
grep -q '^no_model_run=true$' <<<"$verify_curve"

if "$CURVE" --verify-curve-receipt "$tmp/missing-curve.json" >"$tmp/missing-curve.out" 2>"$tmp/missing-curve.err"; then
  echo "expected missing curve receipt to fail verification" >&2
  exit 1
fi
grep -q '^curve_receipt_exists=false$' "$tmp/missing-curve.out"
grep -q '^curve_receipt_schema_ok=false$' "$tmp/missing-curve.out"
grep -q '^schema_issue_count=1$' "$tmp/missing-curve.out"
grep -Fqx 'schema_issue_paths=curve_receipt_exists' "$tmp/missing-curve.out"
grep -q '^curve_receipt_ok=false$' "$tmp/missing-curve.out"
grep -q '^no_model_run=true$' "$tmp/missing-curve.out"
grep -q '^no_scorer_run=true$' "$tmp/missing-curve.out"

printf '{"broken"' >"$tmp/curve-invalid-json.json"
if "$CURVE" --verify-curve-receipt "$tmp/curve-invalid-json.json" >"$tmp/curve-invalid-json.out" 2>"$tmp/curve-invalid-json.err"; then
  echo "expected invalid curve receipt JSON to fail verification" >&2
  exit 1
fi
grep -q '^curve_receipt_exists=true$' "$tmp/curve-invalid-json.out"
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-invalid-json.out"
grep -q '^schema_issue_count=1$' "$tmp/curve-invalid-json.out"
grep -Fqx 'schema_issue_paths=curve_receipt_json' "$tmp/curve-invalid-json.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-invalid-json.out"
grep -q '^no_model_run=true$' "$tmp/curve-invalid-json.out"
grep -q '^no_scorer_run=true$' "$tmp/curve-invalid-json.out"

printf '[]\n' >"$tmp/curve-non-object.json"
if "$CURVE" --verify-curve-receipt "$tmp/curve-non-object.json" >"$tmp/curve-non-object.out" 2>"$tmp/curve-non-object.err"; then
  echo "expected non-object curve receipt to fail verification" >&2
  exit 1
fi
grep -q '^curve_receipt_exists=true$' "$tmp/curve-non-object.out"
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-non-object.out"
grep -q '^schema_issue_count=1$' "$tmp/curve-non-object.out"
grep -Fqx 'schema_issue_paths=curve_receipt_object' "$tmp/curve-non-object.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-non-object.out"
grep -q '^no_model_run=true$' "$tmp/curve-non-object.out"
grep -q '^no_scorer_run=true$' "$tmp/curve-non-object.out"
grep -q '^no_scorer_run=true$' <<<"$verify_curve"

python3 - "$tmp/curve.json" "$tmp/curve-tampered.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["latest_elevation_vs_frontier_solve_rate"] = 0.19
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-tampered.json" >"$tmp/curve-tampered.out" 2>"$tmp/curve-tampered.err"; then
  echo "expected tampered curve receipt to fail" >&2
  exit 1
fi
grep -q '^curve_receipt_ok=false$' "$tmp/curve-tampered.out"
grep -q '^curve_receipt_matches_current=false$' "$tmp/curve-tampered.out"
grep -q '^curve_valid=true$' "$tmp/curve-tampered.out"

python3 - "$tmp/curve.json" "$tmp/curve-missing-verifier-schema.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload.pop("curve_verifier_sha256", None)
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-missing-verifier-schema.json" >"$tmp/curve-missing-verifier-schema.out" 2>"$tmp/curve-missing-verifier-schema.err"; then
  echo "expected curve receipt missing verifier identity to fail schema" >&2
  exit 1
fi
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-missing-verifier-schema.out"
grep -q '^schema_issue_count=1$' "$tmp/curve-missing-verifier-schema.out"
grep -Fqx 'schema_issue_paths=curve_verifier_sha256' "$tmp/curve-missing-verifier-schema.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-missing-verifier-schema.out"

python3 - "$tmp/curve.json" "$tmp/curve-single-point-schema.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["points"] = payload["points"][:1]
payload["round_count"] = 1
payload["curve_valid"] = True
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-single-point-schema.json" >"$tmp/curve-single-point-schema.out" 2>"$tmp/curve-single-point-schema.err"; then
  echo "expected curve receipt with fewer than two points to fail schema" >&2
  exit 1
fi
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-single-point-schema.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-single-point-schema.out"

python3 - "$tmp/curve.json" "$tmp/curve-proof-boolean-schema.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["same_metric_contract"] = False
payload["curve_valid"] = True
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-proof-boolean-schema.json" >"$tmp/curve-proof-boolean-schema.out" 2>"$tmp/curve-proof-boolean-schema.err"; then
  echo "expected curve receipt with false proof boolean to fail schema" >&2
  exit 1
fi
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-proof-boolean-schema.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-proof-boolean-schema.out"

python3 - "$tmp/curve.json" "$tmp/curve-point-proof-schema.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["points"][0]["metric_admissible"] = False
payload["curve_valid"] = True
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-point-proof-schema.json" >"$tmp/curve-point-proof-schema.out" 2>"$tmp/curve-point-proof-schema.err"; then
  echo "expected curve receipt with false point proof to fail schema" >&2
  exit 1
fi
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-point-proof-schema.out"
grep -q '^schema_issue_count=1$' "$tmp/curve-point-proof-schema.out"
grep -Fqx 'schema_issue_paths=points[0].metric_admissible' "$tmp/curve-point-proof-schema.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-point-proof-schema.out"

python3 - "$tmp/curve.json" "$tmp/curve-task-vector-hash-schema.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["points"][0]["task_ids"][0] = "pro__tampered-task-id"
payload["curve_valid"] = True
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-task-vector-hash-schema.json" >"$tmp/curve-task-vector-hash-schema.out" 2>"$tmp/curve-task-vector-hash-schema.err"; then
  echo "expected curve receipt with stale point task-vector hash to fail schema" >&2
  exit 1
fi
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-task-vector-hash-schema.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-task-vector-hash-schema.out"

python3 - "$tmp/curve.json" "$tmp/curve-task-vector-duplicate-schema.json" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["points"][0]["task_ids"][1] = payload["points"][0]["task_ids"][0]
payload["points"][0]["selected_task_ids_sha256"] = hashlib.sha256("\n".join(payload["points"][0]["task_ids"]).encode()).hexdigest()
payload["curve_valid"] = True
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-task-vector-duplicate-schema.json" >"$tmp/curve-task-vector-duplicate-schema.out" 2>"$tmp/curve-task-vector-duplicate-schema.err"; then
  echo "expected curve receipt with duplicate point task IDs to fail schema" >&2
  exit 1
fi
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-task-vector-duplicate-schema.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-task-vector-duplicate-schema.out"

python3 - "$tmp/curve.json" "$tmp/curve-task-vector-mismatch-schema.json" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["points"][0]["task_ids"][0] = "pro__alternate-task-id"
payload["points"][0]["selected_task_ids_sha256"] = hashlib.sha256("\n".join(payload["points"][0]["task_ids"]).encode()).hexdigest()
payload["curve_valid"] = True
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-task-vector-mismatch-schema.json" >"$tmp/curve-task-vector-mismatch-schema.out" 2>"$tmp/curve-task-vector-mismatch-schema.err"; then
  echo "expected curve receipt with mismatched point task vector to fail schema" >&2
  exit 1
fi
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-task-vector-mismatch-schema.out"
grep -q '^same_task_vector=false$' "$tmp/curve-task-vector-mismatch-schema.out"
grep -q '^schema_issue_count=2$' "$tmp/curve-task-vector-mismatch-schema.out"
grep -Fqx 'schema_issue_paths=points[0].selected_task_ids_sha256,points[0].task_ids' "$tmp/curve-task-vector-mismatch-schema.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-task-vector-mismatch-schema.out"

python3 - "$tmp/curve.json" "$tmp/curve-frontier-baseline-mismatch-schema.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["points"][0]["frontier_baseline_sha256"] = "f" * 64
payload["curve_valid"] = True
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-frontier-baseline-mismatch-schema.json" >"$tmp/curve-frontier-baseline-mismatch-schema.out" 2>"$tmp/curve-frontier-baseline-mismatch-schema.err"; then
  echo "expected curve receipt with mismatched frontier baseline to fail schema" >&2
  exit 1
fi
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-frontier-baseline-mismatch-schema.out"
grep -q '^same_frontier_baseline=false$' "$tmp/curve-frontier-baseline-mismatch-schema.out"
grep -q '^schema_issue_count=1$' "$tmp/curve-frontier-baseline-mismatch-schema.out"
grep -Fqx 'schema_issue_paths=points[0].frontier_baseline_sha256' "$tmp/curve-frontier-baseline-mismatch-schema.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-frontier-baseline-mismatch-schema.out"

python3 - "$tmp/curve.json" "$tmp/curve-benchmark-schema.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["points"][0]["benchmark_dataset_name"] = "princeton-nlp/SWE-bench_Verified"
payload["curve_valid"] = True
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-benchmark-schema.json" >"$tmp/curve-benchmark-schema.out" 2>"$tmp/curve-benchmark-schema.err"; then
  echo "expected curve receipt with non-Pro point benchmark to fail schema" >&2
  exit 1
fi
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-benchmark-schema.out"
grep -q '^same_benchmark=false$' "$tmp/curve-benchmark-schema.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-benchmark-schema.out"

python3 - "$tmp/curve.json" "$tmp/curve-metric-contract-schema.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["points"][0]["metric_scope"] = "within_task_efficiency"
payload["points"][0]["within_task_efficiency_metric_admissible"] = True
payload["curve_valid"] = True
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-metric-contract-schema.json" >"$tmp/curve-metric-contract-schema.out" 2>"$tmp/curve-metric-contract-schema.err"; then
  echo "expected curve receipt with within-task point metric to fail schema" >&2
  exit 1
fi
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-metric-contract-schema.out"
grep -q '^same_metric_contract=false$' "$tmp/curve-metric-contract-schema.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-metric-contract-schema.out"

python3 - "$tmp/curve.json" "$tmp/curve-rate-formula-schema.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["points"][0]["elevation_vs_frontier_solve_rate"] = -0.05
payload["elevation_vs_frontier_solve_rates"][0] = -0.05
payload["curve_valid"] = True
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-rate-formula-schema.json" >"$tmp/curve-rate-formula-schema.out" 2>"$tmp/curve-rate-formula-schema.err"; then
  echo "expected curve receipt with inconsistent rate formula to fail schema" >&2
  exit 1
fi
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-rate-formula-schema.out"
grep -q '^rate_formulas_ok=false$' "$tmp/curve-rate-formula-schema.out"
grep -q '^schema_issue_count=1$' "$tmp/curve-rate-formula-schema.out"
grep -Fqx 'schema_issue_paths=points[0].elevation_vs_frontier_solve_rate' "$tmp/curve-rate-formula-schema.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-rate-formula-schema.out"

python3 - "$tmp/curve.json" "$tmp/curve-margin-schema.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["points"][1]["student_solve_rate"] = 0.35
payload["points"][1]["elevation_vs_frontier_solve_rate"] = -0.15
payload["elevation_vs_frontier_solve_rates"][1] = -0.15
payload["curve_valid"] = True
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-margin-schema.json" >"$tmp/curve-margin-schema.out" 2>"$tmp/curve-margin-schema.err"; then
  echo "expected curve receipt with non-growing margin to fail schema" >&2
  exit 1
fi
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-margin-schema.out"
grep -q '^margin_growing=false$' "$tmp/curve-margin-schema.out"
grep -q '^schema_issue_count=1$' "$tmp/curve-margin-schema.out"
grep -Fqx 'schema_issue_paths=points[1].elevation_vs_frontier_solve_rate' "$tmp/curve-margin-schema.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-margin-schema.out"

python3 - "$tmp/curve.json" "$tmp/curve-accumulation-schema.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["points"][1]["accumulation_index"] = 1
payload["accumulation_indices"][1] = 1
payload["curve_valid"] = True
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-accumulation-schema.json" >"$tmp/curve-accumulation-schema.out" 2>"$tmp/curve-accumulation-schema.err"; then
  echo "expected curve receipt with non-increasing accumulation points to fail schema" >&2
  exit 1
fi
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-accumulation-schema.out"
grep -q '^strictly_increasing_accumulation=false$' "$tmp/curve-accumulation-schema.out"
grep -q '^schema_issue_count=1$' "$tmp/curve-accumulation-schema.out"
grep -Fqx "schema_issue_paths=points[1].accumulation_index" "$tmp/curve-accumulation-schema.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-accumulation-schema.out"

python3 - "$tmp/curve.json" "$tmp/curve-axis-schema.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["accumulation_indices"] = [1, 3, 2]
payload["curve_valid"] = True
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-axis-schema.json" >"$tmp/curve-axis-schema.out" 2>"$tmp/curve-axis-schema.err"; then
  echo "expected curve receipt with inconsistent top-level axis to fail schema" >&2
  exit 1
fi
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-axis-schema.out"
grep -q '^schema_issue_count=1$' "$tmp/curve-axis-schema.out"
grep -Fqx 'schema_issue_paths=accumulation_indices' "$tmp/curve-axis-schema.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-axis-schema.out"

python3 - "$tmp/curve.json" "$tmp/curve-missing-round-verifications-schema.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload.pop("round_verifications", None)
payload["curve_valid"] = True
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-missing-round-verifications-schema.json" >"$tmp/curve-missing-round-verifications-schema.out" 2>"$tmp/curve-missing-round-verifications-schema.err"; then
  echo "expected curve receipt missing round verification logs to fail schema" >&2
  exit 1
fi
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-missing-round-verifications-schema.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-missing-round-verifications-schema.out"

python3 - "$tmp/curve.json" "$tmp/curve-short-round-verifications-schema.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["round_verifications"].pop()
payload["curve_valid"] = True
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-short-round-verifications-schema.json" >"$tmp/curve-short-round-verifications-schema.out" 2>"$tmp/curve-short-round-verifications-schema.err"; then
  echo "expected curve receipt with truncated round verification logs to fail schema" >&2
  exit 1
fi
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-short-round-verifications-schema.out"
grep -q '^schema_issue_count=1$' "$tmp/curve-short-round-verifications-schema.out"
grep -Fqx 'schema_issue_paths=round_verifications.count' "$tmp/curve-short-round-verifications-schema.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-short-round-verifications-schema.out"

python3 - "$tmp/curve.json" "$tmp/curve-duplicate-round-verification-schema.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["round_verifications"][1] = dict(payload["round_verifications"][0])
payload["curve_valid"] = True
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-duplicate-round-verification-schema.json" >"$tmp/curve-duplicate-round-verification-schema.out" 2>"$tmp/curve-duplicate-round-verification-schema.err"; then
  echo "expected curve receipt with duplicate round verification log coverage to fail schema" >&2
  exit 1
fi
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-duplicate-round-verification-schema.out"
grep -q '^schema_issue_count=2$' "$tmp/curve-duplicate-round-verification-schema.out"
grep -Fqx 'schema_issue_paths=round_verifications[1].round_receipt_path,round_verifications.missing_round_receipt_path' "$tmp/curve-duplicate-round-verification-schema.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-duplicate-round-verification-schema.out"

python3 - "$tmp/curve.json" "$tmp/curve-round-verification-claim-schema.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["round_verifications"][0]["stdout"] = payload["round_verifications"][0]["stdout"].replace("metric_claim=false", "metric_claim=true", 1)
payload["curve_valid"] = True
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-round-verification-claim-schema.json" >"$tmp/curve-round-verification-claim-schema.out" 2>"$tmp/curve-round-verification-claim-schema.err"; then
  echo "expected curve receipt with claiming round verification log to fail schema" >&2
  exit 1
fi
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-round-verification-claim-schema.out"
grep -q '^schema_issue_count=1$' "$tmp/curve-round-verification-claim-schema.out"
grep -Fqx 'schema_issue_paths=round_verifications[0].stdout.metric_claim' "$tmp/curve-round-verification-claim-schema.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-round-verification-claim-schema.out"

python3 - "$tmp/curve.json" "$tmp/curve-round-verification-stderr-schema.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["round_verifications"][0]["stderr"] = "hidden warning on stderr\n"
payload["curve_valid"] = True
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-round-verification-stderr-schema.json" >"$tmp/curve-round-verification-stderr-schema.out" 2>"$tmp/curve-round-verification-stderr-schema.err"; then
  echo "expected curve receipt with stderr-bearing round verification log to fail schema" >&2
  exit 1
fi
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-round-verification-stderr-schema.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-round-verification-stderr-schema.out"

python3 - "$tmp/curve.json" "$tmp/curve-round-verification-round-ok-schema.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["round_verifications"][0]["stdout"] = payload["round_verifications"][0]["stdout"].replace("round_receipt_ok=true", "round_receipt_ok=false", 1)
payload["curve_valid"] = True
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-round-verification-round-ok-schema.json" >"$tmp/curve-round-verification-round-ok-schema.out" 2>"$tmp/curve-round-verification-round-ok-schema.err"; then
  echo "expected curve receipt with failing round verification log to fail schema" >&2
  exit 1
fi
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-round-verification-round-ok-schema.out"
grep -q '^all_rounds_verified=false$' "$tmp/curve-round-verification-round-ok-schema.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-round-verification-round-ok-schema.out"

python3 - "$tmp/curve.json" "$tmp/curve-round-verification-metric-schema.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["round_verifications"][0]["stdout"] = payload["round_verifications"][0]["stdout"].replace("metric_admissible=true", "metric_admissible=false", 1)
payload["curve_valid"] = True
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-round-verification-metric-schema.json" >"$tmp/curve-round-verification-metric-schema.out" 2>"$tmp/curve-round-verification-metric-schema.err"; then
  echo "expected curve receipt with non-admissible round verification log to fail schema" >&2
  exit 1
fi
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-round-verification-metric-schema.out"
grep -q '^all_rounds_metric_admissible=false$' "$tmp/curve-round-verification-metric-schema.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-round-verification-metric-schema.out"

python3 - "$tmp/curve.json" "$tmp/curve-round-verification-frontier-schema.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["round_verifications"][0]["stdout"] = payload["round_verifications"][0]["stdout"].replace("frontier_summary_verification_ok=true", "frontier_summary_verification_ok=false", 1)
payload["curve_valid"] = True
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-round-verification-frontier-schema.json" >"$tmp/curve-round-verification-frontier-schema.out" 2>"$tmp/curve-round-verification-frontier-schema.err"; then
  echo "expected curve receipt with failing frontier summary verification log to fail schema" >&2
  exit 1
fi
grep -q '^curve_receipt_schema_ok=false$' "$tmp/curve-round-verification-frontier-schema.out"
grep -q '^all_frontier_summaries_verified=false$' "$tmp/curve-round-verification-frontier-schema.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-round-verification-frontier-schema.out"

python3 - "$tmp/curve.json" "$tmp/curve-round-verification-log-tampered.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["round_verifications"][0]["stdout"] += "tampered_log_line=true\n"
payload["curve_valid"] = True
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-round-verification-log-tampered.json" >"$tmp/curve-round-verification-log-tampered.out" 2>"$tmp/curve-round-verification-log-tampered.err"; then
  echo "expected curve receipt with tampered round verification log to fail current replay" >&2
  exit 1
fi
grep -q '^curve_receipt_schema_ok=true$' "$tmp/curve-round-verification-log-tampered.out"
grep -q '^curve_receipt_matches_current=false$' "$tmp/curve-round-verification-log-tampered.out"
grep -q '^stable_projection_matches_current=false$' "$tmp/curve-round-verification-log-tampered.out"
grep -q '^stable_projection_mismatch_count=1$' "$tmp/curve-round-verification-log-tampered.out"
grep -Fqx 'stable_projection_mismatch_paths=round_verifications[1].stdout' "$tmp/curve-round-verification-log-tampered.out"
grep -q '^curve_receipt_ok=false$' "$tmp/curve-round-verification-log-tampered.out"

python3 - "$tmp/curve.json" "$tmp/curve-verifier-tampered.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["curve_verifier_sha256"] = "0" * 64
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-verifier-tampered.json" >"$tmp/curve-verifier-tampered.out" 2>"$tmp/curve-verifier-tampered.err"; then
  echo "expected curve receipt with tampered curve verifier hash to fail" >&2
  exit 1
fi
grep -q '^curve_receipt_ok=false$' "$tmp/curve-verifier-tampered.out"
grep -q '^curve_receipt_matches_current=false$' "$tmp/curve-verifier-tampered.out"
grep -q '^curve_verifier_sha256=0000000000000000000000000000000000000000000000000000000000000000$' "$tmp/curve-verifier-tampered.out"
grep -q '^curve_verifier_identity_ok=false$' "$tmp/curve-verifier-tampered.out"
grep -q '^round_verifier_identity_ok=true$' "$tmp/curve-verifier-tampered.out"

python3 - "$tmp/curve.json" "$tmp/curve-round-verifier-tampered.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["round_verifier_sha256"] = "0" * 64
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-round-verifier-tampered.json" >"$tmp/curve-round-verifier-tampered.out" 2>"$tmp/curve-round-verifier-tampered.err"; then
  echo "expected curve receipt with tampered round verifier hash to fail" >&2
  exit 1
fi
grep -q '^curve_receipt_ok=false$' "$tmp/curve-round-verifier-tampered.out"
grep -q '^curve_receipt_matches_current=false$' "$tmp/curve-round-verifier-tampered.out"
grep -q '^round_verifier_sha256=0000000000000000000000000000000000000000000000000000000000000000$' "$tmp/curve-round-verifier-tampered.out"
grep -q '^curve_verifier_identity_ok=true$' "$tmp/curve-round-verifier-tampered.out"
grep -q '^round_verifier_identity_ok=false$' "$tmp/curve-round-verifier-tampered.out"

python3 - "$tmp/curve.json" "$tmp/curve-frontier-proof-tampered.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
payload = json.loads(src.read_text(encoding="utf-8"))
payload["all_frontier_summaries_verified"] = False
dst.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" --verify-curve-receipt "$tmp/curve-frontier-proof-tampered.json" >"$tmp/curve-frontier-proof-tampered.out" 2>"$tmp/curve-frontier-proof-tampered.err"; then
  echo "expected curve receipt with false frontier-summary aggregate proof to fail" >&2
  exit 1
fi
grep -q '^curve_receipt_ok=false$' "$tmp/curve-frontier-proof-tampered.out"
grep -q '^curve_receipt_matches_current=false$' "$tmp/curve-frontier-proof-tampered.out"
grep -q '^all_frontier_summaries_verified=false$' "$tmp/curve-frontier-proof-tampered.out"

if "$CURVE" "$flat1" "$flat2" >"$tmp/flat.out" 2>"$tmp/flat.err"; then
  echo "expected non-growing curve to fail" >&2
  exit 1
fi
grep -q '^curve_valid=false$' "$tmp/flat.out"
grep -q '^margin_growing=false$' "$tmp/flat.out"
grep -q '^all_rounds_metric_admissible=true$' "$tmp/flat.out"

if "$CURVE" "$r1" "$nonadmissible" >"$tmp/nonadmissible.out" 2>"$tmp/nonadmissible.err"; then
  echo "expected non-admissible round to fail curve verification" >&2
  exit 1
fi
grep -q '^curve_valid=false$' "$tmp/nonadmissible.out"
grep -q '^all_rounds_metric_admissible=false$' "$tmp/nonadmissible.out"

stale_summary="$tmp/stale-frontier-summary.json"
stale_receipt="$tmp/stale-frontier-summary-round-receipt.json"
python3 - "$r1" "$stale_summary" "$stale_receipt" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

source_receipt = Path(sys.argv[1])
stale_summary = Path(sys.argv[2])
stale_receipt = Path(sys.argv[3])

receipt = json.loads(source_receipt.read_text(encoding="utf-8"))
summary = json.loads(Path(receipt["frontier_baseline_summary_path"]).read_text(encoding="utf-8"))
summary["frontier_baseline_sha256"] = "0" * 64
stale_summary.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")

receipt["frontier_baseline_summary_path"] = str(stale_summary)
receipt["frontier_baseline_summary_sha256"] = hashlib.sha256(stale_summary.read_bytes()).hexdigest()
receipt["round_receipt_path"] = str(stale_receipt)
stale_receipt.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$CURVE" "$r1" "$stale_receipt" >"$tmp/stale-frontier-summary-curve.out" 2>"$tmp/stale-frontier-summary-curve.err"; then
  echo "expected curve with stale frontier summary verification to fail" >&2
  exit 1
fi
grep -q '^curve_valid=false$' "$tmp/stale-frontier-summary-curve.out"
grep -q '^all_rounds_verified=false$' "$tmp/stale-frontier-summary-curve.out"
grep -q '^all_frontier_summaries_verified=false$' "$tmp/stale-frontier-summary-curve.out"

echo "Pro elevation curve contract ok"
