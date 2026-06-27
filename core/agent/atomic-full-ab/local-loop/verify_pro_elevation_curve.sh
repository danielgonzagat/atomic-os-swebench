#!/usr/bin/env bash
# verify_pro_elevation_curve.sh - verify the Pro paired-frontier delta curve from round receipts.
set -euo pipefail

HERE="/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"
ROUND_VERIFIER="${ATOMIC_PRO_ROUND_VERIFIER:-$HERE/run_pro_elevation_round.sh}"
SWE_PYTHON="${SWE_PYTHON:-/opt/homebrew/bin/python3}"

sha256_file_if_present() {
  [[ -f "$1" ]] || return 0
  "$SWE_PYTHON" - "$1" <<'PYHASH'
import hashlib
import sys
with open(sys.argv[1], "rb") as handle:
    print(hashlib.sha256(handle.read()).hexdigest())
PYHASH
}

if [[ "${1:-}" == "--selftest" ]]; then
  curve_verifier_path="${BASH_SOURCE[0]}"
  curve_verifier_sha256="$(sha256_file_if_present "$curve_verifier_path")"
  round_verifier_sha256="$(sha256_file_if_present "$ROUND_VERIFIER")"
  cat <<EOF
metric=pro_elevation_delta_curve_verifier
metric_claim=false
input=pro_elevation_round_receipts
requires_round_receipt_ok=true
requires_metric_admissible=true
requires_frontier_summary_verification_ok=true
requires_round_verifications=true
requires_current_replay=true
curve_verifier_path=$curve_verifier_path
curve_verifier_sha256=$curve_verifier_sha256
round_verifier_path=$ROUND_VERIFIER
round_verifier_sha256=$round_verifier_sha256
curve_axis=accumulation_index
curve_y=elevation_vs_frontier_solve_rate
summary_fields=metric,metric_claim,curve_valid,round_count,all_rounds_verified,all_rounds_metric_admissible,all_frontier_summaries_verified,curve_verifier_path,curve_verifier_sha256,curve_verifier_identity_ok,round_verifier_path,round_verifier_sha256,round_verifier_identity_ok,stable_projection_matches_current,stable_projection_mismatch_count,stable_projection_mismatch_paths,schema_issue_count,schema_issue_paths,same_task_vector,same_frontier_baseline,same_benchmark,same_metric_contract,rate_formulas_ok,strictly_increasing_accumulation,margin_growing,accumulation_indices,elevation_vs_frontier_solve_rates,latest_elevation_vs_frontier_solve_rate,round_verifications,curve_receipt_path
no_model_run=true
no_scorer_run=true
EOF
  exit 0
fi

if [[ "${1:-}" == "--verify-curve-receipt" ]]; then
  curve_receipt="${2:-}"
  "$SWE_PYTHON" - "${BASH_SOURCE[0]}" "$curve_receipt" "$ROUND_VERIFIER" <<'PYCURVEVERIFY'
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

script_path = str(Path(sys.argv[1]).resolve())
curve_receipt_path = sys.argv[2] if len(sys.argv) > 2 else ""
round_verifier_current_path = str(Path(sys.argv[3]).resolve()) if len(sys.argv) > 3 else ""


def bool_text(value):
    return "true" if value else "false"


def nonempty_string(value):
    return isinstance(value, str) and bool(value)


def sha256_hex(value):
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(char in "0123456789abcdef" for char in value.lower())
    )


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def int_value(value):
    return isinstance(value, int) and not isinstance(value, bool)


def close(left, right):
    return number(left) and number(right) and abs(float(left) - float(right)) <= 1e-12


def sha256_file(path):
    if not path or not Path(path).is_file():
        return ""
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def task_ids_sha256_ok(task_ids, expected):
    if not isinstance(task_ids, list) or not sha256_hex(expected):
        return False
    if len(task_ids) != len(set(task_ids)):
        return False
    actual = hashlib.sha256("\n".join(task_ids).encode()).hexdigest()
    return actual == expected


def same_task_vector_schema_ok(points):
    if not isinstance(points, list) or not points:
        return False
    first = points[0]
    if not isinstance(first, dict):
        return False
    first_hash = first.get("selected_task_ids_sha256")
    first_task_ids = first.get("task_ids")
    return all(
        isinstance(point, dict)
        and point.get("selected_task_ids_sha256") == first_hash
        and point.get("task_ids") == first_task_ids
        for point in points
    )


def task_vector_schema_issue_paths(points):
    if not isinstance(points, list) or not points:
        return ["same_task_vector"]

    keys = []
    for point in points:
        if not isinstance(point, dict):
            continue
        task_ids = point.get("task_ids")
        task_key = tuple(task_ids) if isinstance(task_ids, list) else None
        keys.append((point.get("selected_task_ids_sha256"), task_key))
    if not keys:
        return ["same_task_vector"]

    expected_hash, expected_task_key = max(keys, key=keys.count)
    issues = []

    def add(path_name):
        if path_name not in issues:
            issues.append(path_name)

    for idx, point in enumerate(points):
        prefix = f"points[{idx}]"
        if not isinstance(point, dict):
            add(prefix)
            continue
        task_ids = point.get("task_ids")
        task_key = tuple(task_ids) if isinstance(task_ids, list) else None
        if point.get("selected_task_ids_sha256") != expected_hash:
            add(f"{prefix}.selected_task_ids_sha256")
        if task_key != expected_task_key:
            add(f"{prefix}.task_ids")
    if not issues and not same_task_vector_schema_ok(points):
        add("same_task_vector")
    return issues


def same_frontier_baseline_schema_ok(points):
    if not isinstance(points, list) or not points:
        return False
    first = points[0]
    if not isinstance(first, dict):
        return False
    first_hash = first.get("frontier_baseline_sha256")
    first_rate = first.get("frontier_solve_rate")
    return all(
        isinstance(point, dict)
        and point.get("frontier_baseline_sha256") == first_hash
        and close(point.get("frontier_solve_rate"), first_rate)
        for point in points
    )


def frontier_baseline_schema_issue_paths(points):
    if not isinstance(points, list) or not points:
        return ["same_frontier_baseline"]

    keys = []
    for point in points:
        if not isinstance(point, dict):
            continue
        rate = point.get("frontier_solve_rate")
        rate_key = round(float(rate), 12) if number(rate) else rate
        keys.append((point.get("frontier_baseline_sha256"), rate_key))
    if not keys:
        return ["same_frontier_baseline"]

    expected_hash, expected_rate = max(keys, key=keys.count)
    issues = []

    def add(path_name):
        if path_name not in issues:
            issues.append(path_name)

    for idx, point in enumerate(points):
        prefix = f"points[{idx}]"
        if not isinstance(point, dict):
            add(prefix)
            continue
        if point.get("frontier_baseline_sha256") != expected_hash:
            add(f"{prefix}.frontier_baseline_sha256")
        if not close(point.get("frontier_solve_rate"), expected_rate):
            add(f"{prefix}.frontier_solve_rate")
    if not issues and not same_frontier_baseline_schema_ok(points):
        add("same_frontier_baseline")
    return issues


def same_benchmark_schema_ok(points):
    if not isinstance(points, list) or not points:
        return False
    return all(
        isinstance(point, dict)
        and point.get("benchmark_suite") == "swe_bench_pro"
        and point.get("benchmark_dataset_name") == "ScaleAI/SWE-bench_Pro"
        and point.get("student_model") == "deepseek-v4-pro"
        for point in points
    )


def same_metric_contract_schema_ok(points):
    if not isinstance(points, list) or not points:
        return False
    return all(
        isinstance(point, dict)
        and point.get("metric_scope") == "paired_frontier_solve_rate_delta"
        and point.get("within_task_efficiency_metric_admissible") is False
        for point in points
    )


def rate_formulas_schema_ok(points):
    if not isinstance(points, list) or not points:
        return False
    for point in points:
        if not isinstance(point, dict):
            return False
        student_rate = point.get("student_solve_rate")
        frontier_rate = point.get("frontier_solve_rate")
        if not number(student_rate) or not number(frontier_rate):
            return False
        if not close(point.get("elevation_vs_frontier_solve_rate"), float(student_rate) - float(frontier_rate)):
            return False
    return True


def rate_formula_schema_issue_paths(points):
    if not isinstance(points, list) or not points:
        return ["rate_formulas_ok"]

    issues = []

    def add(path_name):
        if path_name not in issues:
            issues.append(path_name)

    for idx, point in enumerate(points):
        prefix = f"points[{idx}]"
        if not isinstance(point, dict):
            add(prefix)
            continue
        student_rate = point.get("student_solve_rate")
        frontier_rate = point.get("frontier_solve_rate")
        if not number(student_rate):
            add(f"{prefix}.student_solve_rate")
        if not number(frontier_rate):
            add(f"{prefix}.frontier_solve_rate")
        if number(student_rate) and number(frontier_rate) and not close(
            point.get("elevation_vs_frontier_solve_rate"),
            float(student_rate) - float(frontier_rate),
        ):
            add(f"{prefix}.elevation_vs_frontier_solve_rate")
    if not issues and not rate_formulas_schema_ok(points):
        add("rate_formulas_ok")
    return issues


def strictly_increasing_accumulation_schema_ok(points):
    if not isinstance(points, list) or len(points) < 2:
        return False
    indices = []
    for point in points:
        if not isinstance(point, dict) or not int_value(point.get("accumulation_index")):
            return False
        indices.append(point.get("accumulation_index"))
    return all(indices[idx] < indices[idx + 1] for idx in range(len(indices) - 1))


def accumulation_schema_issue_paths(points):
    if not isinstance(points, list) or len(points) < 2:
        return ["strictly_increasing_accumulation"]

    issues = []

    def add(path_name):
        if path_name not in issues:
            issues.append(path_name)

    previous = None
    for idx, point in enumerate(points):
        prefix = f"points[{idx}]"
        if not isinstance(point, dict):
            add(prefix)
            previous = None
            continue
        current = point.get("accumulation_index")
        if not int_value(current):
            add(f"{prefix}.accumulation_index")
            previous = None
            continue
        if previous is not None and previous >= current:
            add(f"{prefix}.accumulation_index")
        previous = current
    if not issues and not strictly_increasing_accumulation_schema_ok(points):
        add("strictly_increasing_accumulation")
    return issues


def margin_growing_schema_ok(points):
    if not isinstance(points, list) or len(points) < 2:
        return False
    rates = []
    for point in points:
        if not isinstance(point, dict) or not number(point.get("elevation_vs_frontier_solve_rate")):
            return False
        rates.append(float(point.get("elevation_vs_frontier_solve_rate")))
    return all(rates[idx] < rates[idx + 1] for idx in range(len(rates) - 1))


def margin_schema_issue_paths(points):
    if not isinstance(points, list) or len(points) < 2:
        return ["margin_growing"]

    issues = []

    def add(path_name):
        if path_name not in issues:
            issues.append(path_name)

    previous = None
    for idx, point in enumerate(points):
        prefix = f"points[{idx}]"
        if not isinstance(point, dict):
            add(prefix)
            previous = None
            continue
        current = point.get("elevation_vs_frontier_solve_rate")
        if not number(current):
            add(f"{prefix}.elevation_vs_frontier_solve_rate")
            previous = None
            continue
        current = float(current)
        if previous is not None and previous >= current:
            add(f"{prefix}.elevation_vs_frontier_solve_rate")
        previous = current
    if not issues and not margin_growing_schema_ok(points):
        add("margin_growing")
    return issues


def curve_axes_schema_ok(receipt, points):
    if not isinstance(points, list):
        return False
    accumulation_indices = receipt.get("accumulation_indices")
    solve_rates = receipt.get("elevation_vs_frontier_solve_rates")
    latest = receipt.get("latest_elevation_vs_frontier_solve_rate")
    point_indices = [point.get("accumulation_index") for point in points if isinstance(point, dict)]
    point_rates = [point.get("elevation_vs_frontier_solve_rate") for point in points if isinstance(point, dict)]
    return (
        isinstance(accumulation_indices, list)
        and isinstance(solve_rates, list)
        and accumulation_indices == point_indices
        and len(solve_rates) == len(point_rates)
        and all(number(rate) for rate in solve_rates)
        and all(close(left, right) for left, right in zip(solve_rates, point_rates))
        and bool(solve_rates)
        and close(latest, solve_rates[-1])
    )


def curve_axis_schema_issue_paths(receipt, points):
    if not isinstance(points, list):
        return ["curve_axes"]

    issues = []

    def add(path_name):
        if path_name not in issues:
            issues.append(path_name)

    accumulation_indices = receipt.get("accumulation_indices")
    solve_rates = receipt.get("elevation_vs_frontier_solve_rates")
    latest = receipt.get("latest_elevation_vs_frontier_solve_rate")
    point_indices = [point.get("accumulation_index") for point in points if isinstance(point, dict)]
    point_rates = [point.get("elevation_vs_frontier_solve_rate") for point in points if isinstance(point, dict)]

    if not isinstance(accumulation_indices, list) or accumulation_indices != point_indices:
        add("accumulation_indices")
    if (
        not isinstance(solve_rates, list)
        or len(solve_rates) != len(point_rates)
        or not all(number(rate) for rate in solve_rates)
        or not all(close(left, right) for left, right in zip(solve_rates, point_rates))
    ):
        add("elevation_vs_frontier_solve_rates")
    if not isinstance(solve_rates, list) or not solve_rates or not close(latest, solve_rates[-1]):
        add("latest_elevation_vs_frontier_solve_rate")
    return issues


def point_schema_ok(point):
    task_ids = point.get("task_ids") if isinstance(point, dict) else None
    return (
        isinstance(point, dict)
        and nonempty_string(point.get("round_receipt_path"))
        and sha256_hex(point.get("round_receipt_sha256"))
        and point.get("round_receipt_ok") is True
        and point.get("metric_admissible") is True
        and point.get("frontier_summary_verification_ok") is True
        and nonempty_string(point.get("run_id"))
        and point.get("benchmark_suite") == "swe_bench_pro"
        and point.get("benchmark_dataset_name") == "ScaleAI/SWE-bench_Pro"
        and point.get("metric_scope") == "paired_frontier_solve_rate_delta"
        and point.get("within_task_efficiency_metric_admissible") is False
        and point.get("student_model") == "deepseek-v4-pro"
        and sha256_hex(point.get("selected_task_ids_sha256"))
        and isinstance(task_ids, list)
        and len(task_ids) > 0
        and all(nonempty_string(task_id) for task_id in task_ids)
        and task_ids_sha256_ok(task_ids, point.get("selected_task_ids_sha256"))
        and sha256_hex(point.get("frontier_baseline_sha256"))
        and number(point.get("frontier_solve_rate"))
        and number(point.get("student_solve_rate"))
        and number(point.get("elevation_vs_frontier_solve_rate"))
        and int_value(point.get("elevation_vs_frontier"))
        and int_value(point.get("accumulation_index"))
        and int_value(point.get("substrate_weight_count"))
    )


def point_schema_issue_paths(point, index):
    prefix = f"points[{index}]"
    if not isinstance(point, dict):
        return [prefix]

    issues = []

    def add(field):
        issues.append(f"{prefix}.{field}")

    task_ids = point.get("task_ids")
    if not nonempty_string(point.get("round_receipt_path")):
        add("round_receipt_path")
    if not sha256_hex(point.get("round_receipt_sha256")):
        add("round_receipt_sha256")
    if point.get("round_receipt_ok") is not True:
        add("round_receipt_ok")
    if point.get("metric_admissible") is not True:
        add("metric_admissible")
    if point.get("frontier_summary_verification_ok") is not True:
        add("frontier_summary_verification_ok")
    if not nonempty_string(point.get("run_id")):
        add("run_id")
    if point.get("benchmark_suite") != "swe_bench_pro":
        add("benchmark_suite")
    if point.get("benchmark_dataset_name") != "ScaleAI/SWE-bench_Pro":
        add("benchmark_dataset_name")
    if point.get("metric_scope") != "paired_frontier_solve_rate_delta":
        add("metric_scope")
    if point.get("within_task_efficiency_metric_admissible") is not False:
        add("within_task_efficiency_metric_admissible")
    if point.get("student_model") != "deepseek-v4-pro":
        add("student_model")
    if not sha256_hex(point.get("selected_task_ids_sha256")):
        add("selected_task_ids_sha256")
    if (
        not isinstance(task_ids, list)
        or len(task_ids) <= 0
        or not all(nonempty_string(task_id) for task_id in task_ids)
        or not task_ids_sha256_ok(task_ids, point.get("selected_task_ids_sha256"))
    ):
        add("task_ids")
    if not sha256_hex(point.get("frontier_baseline_sha256")):
        add("frontier_baseline_sha256")
    if not number(point.get("frontier_solve_rate")):
        add("frontier_solve_rate")
    if not number(point.get("student_solve_rate")):
        add("student_solve_rate")
    if not number(point.get("elevation_vs_frontier_solve_rate")):
        add("elevation_vs_frontier_solve_rate")
    if not int_value(point.get("elevation_vs_frontier")):
        add("elevation_vs_frontier")
    if not int_value(point.get("accumulation_index")):
        add("accumulation_index")
    if not int_value(point.get("substrate_weight_count")):
        add("substrate_weight_count")
    return issues


def parse_kv(text):
    parsed = {}
    if not isinstance(text, str):
        return parsed
    for line in text.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            parsed[key] = value
    return parsed


def round_verification_aggregate_status(receipt, points):
    false_status = {
        "all_rounds_verified": False,
        "all_rounds_metric_admissible": False,
        "all_frontier_summaries_verified": False,
    }
    if not isinstance(points, list):
        return false_status
    verifications = receipt.get("round_verifications")
    if not isinstance(verifications, list) or len(verifications) != len(points):
        return false_status
    points_by_path = {
        point.get("round_receipt_path"): point
        for point in points
        if isinstance(point, dict) and nonempty_string(point.get("round_receipt_path"))
    }
    if len(points_by_path) != len(points):
        return false_status
    seen = set()
    all_rounds_verified = True
    all_rounds_metric_admissible = True
    all_frontier_summaries_verified = True
    for verification in verifications:
        if not isinstance(verification, dict):
            return false_status
        path = verification.get("round_receipt_path")
        if not nonempty_string(path) or path not in points_by_path or path in seen:
            return false_status
        seen.add(path)
        stdout = verification.get("stdout")
        stderr = verification.get("stderr")
        if verification.get("returncode") != 0 or not isinstance(stdout, str) or stderr != "":
            return false_status
        parsed = parse_kv(stdout)
        point = points_by_path[path]
        if (
            parsed.get("metric") != "pro_elevation_round_receipt_verification"
            or parsed.get("metric_claim") != "false"
            or parsed.get("round_receipt_path") != path
            or parsed.get("round_receipt_sha256") != point.get("round_receipt_sha256")
            or parsed.get("no_model_run") != "true"
            or parsed.get("no_scorer_run") != "true"
        ):
            return false_status
        all_rounds_verified = all_rounds_verified and parsed.get("round_receipt_ok") == "true"
        all_rounds_metric_admissible = all_rounds_metric_admissible and parsed.get("metric_admissible") == "true"
        all_frontier_summaries_verified = all_frontier_summaries_verified and parsed.get("frontier_summary_verification_ok") == "true"
    if seen != set(points_by_path):
        return false_status
    return {
        "all_rounds_verified": all_rounds_verified,
        "all_rounds_metric_admissible": all_rounds_metric_admissible,
        "all_frontier_summaries_verified": all_frontier_summaries_verified,
    }


def round_verification_schema_issue_paths(receipt, points):
    issues = []

    def add(path_name):
        if path_name not in issues:
            issues.append(path_name)

    if not isinstance(points, list):
        return ["round_verifications"]
    verifications = receipt.get("round_verifications")
    if not isinstance(verifications, list):
        return ["round_verifications"]
    count_matches = len(verifications) == len(points)
    if not count_matches:
        add("round_verifications.count")

    points_by_path = {
        point.get("round_receipt_path"): point
        for point in points
        if isinstance(point, dict) and nonempty_string(point.get("round_receipt_path"))
    }
    if len(points_by_path) != len(points):
        add("points.round_receipt_path")

    seen = set()
    for idx, verification in enumerate(verifications):
        prefix = f"round_verifications[{idx}]"
        if not isinstance(verification, dict):
            add(prefix)
            continue

        path = verification.get("round_receipt_path")
        point = None
        if not nonempty_string(path) or path not in points_by_path or path in seen:
            add(f"{prefix}.round_receipt_path")
        else:
            point = points_by_path[path]
            seen.add(path)

        stdout = verification.get("stdout")
        stderr = verification.get("stderr")
        if verification.get("returncode") != 0:
            add(f"{prefix}.returncode")
        if not isinstance(stdout, str):
            add(f"{prefix}.stdout")
        if stderr != "":
            add(f"{prefix}.stderr")
        if not isinstance(stdout, str):
            continue

        parsed = parse_kv(stdout)
        if parsed.get("metric") != "pro_elevation_round_receipt_verification":
            add(f"{prefix}.stdout.metric")
        if parsed.get("metric_claim") != "false":
            add(f"{prefix}.stdout.metric_claim")
        if parsed.get("round_receipt_path") != path:
            add(f"{prefix}.stdout.round_receipt_path")
        if point is not None and parsed.get("round_receipt_sha256") != point.get("round_receipt_sha256"):
            add(f"{prefix}.stdout.round_receipt_sha256")
        if parsed.get("no_model_run") != "true":
            add(f"{prefix}.stdout.no_model_run")
        if parsed.get("no_scorer_run") != "true":
            add(f"{prefix}.stdout.no_scorer_run")
        if parsed.get("round_receipt_ok") != "true":
            add(f"{prefix}.stdout.round_receipt_ok")
        if parsed.get("metric_admissible") != "true":
            add(f"{prefix}.stdout.metric_admissible")
        if parsed.get("frontier_summary_verification_ok") != "true":
            add(f"{prefix}.stdout.frontier_summary_verification_ok")

    if count_matches and seen != set(points_by_path):
        add("round_verifications.missing_round_receipt_path")
    return issues


def round_verifications_schema_ok(receipt, points):
    status = round_verification_aggregate_status(receipt, points)
    return (
        status["all_rounds_verified"]
        and status["all_rounds_metric_admissible"]
        and status["all_frontier_summaries_verified"]
    )


def stable_round_verifications(receipt):
    verifications = receipt.get("round_verifications")
    if not isinstance(verifications, list):
        return []
    stable = []
    for verification in verifications:
        if not isinstance(verification, dict):
            continue
        stable.append({
            "round_receipt_path": verification.get("round_receipt_path"),
            "returncode": verification.get("returncode"),
            "stdout": verification.get("stdout"),
            "stderr": verification.get("stderr"),
        })
    return sorted(stable, key=lambda item: item.get("round_receipt_path") or "")


def emit(
    *,
    exists=False,
    schema_ok=False,
    matches_current=False,
    receipt_ok=False,
    curve_valid=False,
    round_count=0,
    all_rounds_verified=False,
    all_rounds_metric_admissible=False,
    all_frontier_summaries_verified=False,
    same_task_vector=False,
    same_frontier_baseline=False,
    same_benchmark=False,
    same_metric_contract=False,
    rate_formulas_ok=False,
    strictly_increasing_accumulation=False,
    margin_growing=False,
    curve_verifier_path="",
    curve_verifier_sha256="",
    curve_verifier_identity_ok=False,
    round_verifier_path="",
    round_verifier_sha256="",
    round_verifier_identity_ok=False,
    stable_projection_matches_current=False,
    stable_projection_mismatch_count=0,
    stable_projection_mismatch_paths="",
    schema_issue_count=0,
    schema_issue_paths="",
):
    print("metric=pro_elevation_delta_curve_receipt_verification")
    print("metric_claim=false")
    print(f"curve_receipt_path={curve_receipt_path}")
    print(f"curve_receipt_exists={bool_text(exists)}")
    print(f"curve_receipt_schema_ok={bool_text(schema_ok)}")
    print(f"schema_issue_count={schema_issue_count}")
    print(f"schema_issue_paths={schema_issue_paths}")
    print(f"curve_receipt_matches_current={bool_text(matches_current)}")
    print(f"stable_projection_matches_current={bool_text(stable_projection_matches_current)}")
    print(f"stable_projection_mismatch_count={stable_projection_mismatch_count}")
    print(f"stable_projection_mismatch_paths={stable_projection_mismatch_paths}")
    print(f"curve_receipt_ok={bool_text(receipt_ok)}")
    print(f"curve_valid={bool_text(curve_valid)}")
    print(f"round_count={round_count}")
    print(f"all_rounds_verified={bool_text(all_rounds_verified)}")
    print(f"all_rounds_metric_admissible={bool_text(all_rounds_metric_admissible)}")
    print(f"all_frontier_summaries_verified={bool_text(all_frontier_summaries_verified)}")
    print(f"same_task_vector={bool_text(same_task_vector)}")
    print(f"same_frontier_baseline={bool_text(same_frontier_baseline)}")
    print(f"same_benchmark={bool_text(same_benchmark)}")
    print(f"same_metric_contract={bool_text(same_metric_contract)}")
    print(f"rate_formulas_ok={bool_text(rate_formulas_ok)}")
    print(f"strictly_increasing_accumulation={bool_text(strictly_increasing_accumulation)}")
    print(f"margin_growing={bool_text(margin_growing)}")
    print(f"curve_verifier_path={curve_verifier_path}")
    print(f"curve_verifier_sha256={curve_verifier_sha256}")
    print(f"curve_verifier_identity_ok={bool_text(curve_verifier_identity_ok)}")
    print(f"round_verifier_path={round_verifier_path}")
    print(f"round_verifier_sha256={round_verifier_sha256}")
    print(f"round_verifier_identity_ok={bool_text(round_verifier_identity_ok)}")
    print("no_model_run=true")
    print("no_scorer_run=true")


def stable_projection(receipt):
    top_fields = [
        "metric",
        "metric_claim",
        "curve_valid",
        "round_count",
        "all_rounds_verified",
        "all_rounds_metric_admissible",
        "all_frontier_summaries_verified",
        "curve_verifier_path",
        "curve_verifier_sha256",
        "round_verifier_path",
        "round_verifier_sha256",
        "same_task_vector",
        "same_frontier_baseline",
        "same_benchmark",
        "same_metric_contract",
        "rate_formulas_ok",
        "strictly_increasing_accumulation",
        "margin_growing",
        "accumulation_indices",
        "elevation_vs_frontier_solve_rates",
        "latest_elevation_vs_frontier_solve_rate",
        "no_model_run",
        "no_scorer_run",
    ]
    point_fields = [
        "round_receipt_path",
        "round_receipt_sha256",
        "round_receipt_ok",
        "metric_admissible",
        "frontier_summary_verification_ok",
        "run_id",
        "benchmark_suite",
        "benchmark_dataset_name",
        "metric_scope",
        "within_task_efficiency_metric_admissible",
        "student_model",
        "selected_task_ids_sha256",
        "task_ids",
        "frontier_baseline_sha256",
        "frontier_solve_rate",
        "student_solve_rate",
        "elevation_vs_frontier_solve_rate",
        "elevation_vs_frontier",
        "accumulation_index",
        "substrate_weight_count",
    ]
    points = receipt.get("points")
    if not isinstance(points, list):
        points = []
    return {
        "top": {field: receipt.get(field) for field in top_fields},
        "points": [
            {field: point.get(field) for field in point_fields}
            for point in points
            if isinstance(point, dict)
        ],
        "round_verifications": stable_round_verifications(receipt),
    }


def stable_projection_diff_paths(left, right, path=""):
    if isinstance(left, dict) and isinstance(right, dict):
        paths = []
        for key in sorted(set(left) | set(right)):
            child_path = f"{path}.{key}" if path else str(key)
            paths.extend(stable_projection_diff_paths(left.get(key), right.get(key), child_path))
        return paths
    if isinstance(left, list) and isinstance(right, list):
        paths = []
        for idx in range(max(len(left), len(right))):
            left_value = left[idx] if idx < len(left) else None
            right_value = right[idx] if idx < len(right) else None
            paths.extend(stable_projection_diff_paths(left_value, right_value, f"{path}[{idx}]"))
        return paths
    return [] if left == right else [path or "$"]


def schema_issue_paths_for(receipt, points):
    issues = []

    def add(path_name):
        if path_name not in issues:
            issues.append(path_name)

    def expect(condition, path_name):
        if not condition:
            add(path_name)

    expect(receipt.get("metric") == "pro_elevation_delta_curve", "metric")
    expect(receipt.get("metric_claim") is False, "metric_claim")
    expect(receipt.get("no_model_run") is True, "no_model_run")
    expect(receipt.get("no_scorer_run") is True, "no_scorer_run")
    expect(receipt.get("curve_valid") is True, "curve_valid")
    expect(receipt.get("all_rounds_verified") is True, "all_rounds_verified")
    expect(receipt.get("all_rounds_metric_admissible") is True, "all_rounds_metric_admissible")
    expect(receipt.get("all_frontier_summaries_verified") is True, "all_frontier_summaries_verified")
    expect(receipt.get("same_task_vector") is True, "same_task_vector")
    expect(receipt.get("same_frontier_baseline") is True, "same_frontier_baseline")
    expect(receipt.get("same_benchmark") is True, "same_benchmark")
    expect(receipt.get("same_metric_contract") is True, "same_metric_contract")
    expect(receipt.get("rate_formulas_ok") is True, "rate_formulas_ok")
    expect(receipt.get("strictly_increasing_accumulation") is True, "strictly_increasing_accumulation")
    expect(receipt.get("margin_growing") is True, "margin_growing")
    expect(nonempty_string(receipt.get("curve_verifier_path")), "curve_verifier_path")
    expect(sha256_hex(receipt.get("curve_verifier_sha256")), "curve_verifier_sha256")
    expect(nonempty_string(receipt.get("round_verifier_path")), "round_verifier_path")
    expect(sha256_hex(receipt.get("round_verifier_sha256")), "round_verifier_sha256")

    if not isinstance(points, list):
        add("points")
        return issues

    expect(len(points) >= 2, "points")
    round_count_value = receipt.get("round_count")
    round_count_is_int = isinstance(round_count_value, int) and not isinstance(round_count_value, bool)
    expect(round_count_is_int, "round_count")
    if round_count_is_int:
        expect(round_count_value == len(points), "round_count")
    for idx, point in enumerate(points):
        for issue_path in point_schema_issue_paths(point, idx):
            add(issue_path)
    for issue_path in task_vector_schema_issue_paths(points):
        add(issue_path)
    for issue_path in frontier_baseline_schema_issue_paths(points):
        add(issue_path)
    expect(same_benchmark_schema_ok(points), "same_benchmark")
    expect(same_metric_contract_schema_ok(points), "same_metric_contract")
    for issue_path in rate_formula_schema_issue_paths(points):
        add(issue_path)
    for issue_path in accumulation_schema_issue_paths(points):
        add(issue_path)
    for issue_path in margin_schema_issue_paths(points):
        add(issue_path)
    for issue_path in curve_axis_schema_issue_paths(receipt, points):
        add(issue_path)
    for issue_path in round_verification_schema_issue_paths(receipt, points):
        add(issue_path)
    return issues


path = Path(curve_receipt_path)
if not curve_receipt_path or not path.is_file():
    emit(
        schema_issue_count=1,
        schema_issue_paths="curve_receipt_exists",
    )
    raise SystemExit(2)

try:
    receipt = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    emit(
        exists=True,
        schema_issue_count=1,
        schema_issue_paths="curve_receipt_json",
    )
    raise SystemExit(2)

if not isinstance(receipt, dict):
    emit(
        exists=True,
        schema_issue_count=1,
        schema_issue_paths="curve_receipt_object",
    )
    raise SystemExit(2)

points = receipt.get("points")
schema_issue_paths = schema_issue_paths_for(receipt, points)
schema_ok = (
    receipt.get("metric") == "pro_elevation_delta_curve"
    and receipt.get("metric_claim") is False
    and receipt.get("no_model_run") is True
    and receipt.get("no_scorer_run") is True
    and receipt.get("curve_valid") is True
    and receipt.get("all_rounds_verified") is True
    and receipt.get("all_rounds_metric_admissible") is True
    and receipt.get("all_frontier_summaries_verified") is True
    and receipt.get("same_task_vector") is True
    and receipt.get("same_frontier_baseline") is True
    and receipt.get("same_benchmark") is True
    and receipt.get("same_metric_contract") is True
    and receipt.get("rate_formulas_ok") is True
    and receipt.get("strictly_increasing_accumulation") is True
    and receipt.get("margin_growing") is True
    and nonempty_string(receipt.get("curve_verifier_path"))
    and sha256_hex(receipt.get("curve_verifier_sha256"))
    and nonempty_string(receipt.get("round_verifier_path"))
    and sha256_hex(receipt.get("round_verifier_sha256"))
    and isinstance(points, list)
    and len(points) >= 2
    and isinstance(receipt.get("round_count"), int)
    and not isinstance(receipt.get("round_count"), bool)
    and receipt.get("round_count") == len(points)
    and all(point_schema_ok(point) for point in points)
    and same_task_vector_schema_ok(points)
    and same_frontier_baseline_schema_ok(points)
    and same_benchmark_schema_ok(points)
    and same_metric_contract_schema_ok(points)
    and rate_formulas_schema_ok(points)
    and strictly_increasing_accumulation_schema_ok(points)
    and margin_growing_schema_ok(points)
    and curve_axes_schema_ok(receipt, points)
    and round_verifications_schema_ok(receipt, points)
)
curve_valid = receipt.get("curve_valid") is True
round_count = receipt.get("round_count") if isinstance(receipt.get("round_count"), int) and not isinstance(receipt.get("round_count"), bool) else 0
round_verification_status = round_verification_aggregate_status(receipt, points)
all_rounds_verified = receipt.get("all_rounds_verified") is True and round_verification_status["all_rounds_verified"]
all_rounds_metric_admissible = receipt.get("all_rounds_metric_admissible") is True and round_verification_status["all_rounds_metric_admissible"]
all_frontier_summaries_verified = receipt.get("all_frontier_summaries_verified") is True and round_verification_status["all_frontier_summaries_verified"]
same_task_vector = receipt.get("same_task_vector") is True and same_task_vector_schema_ok(points)
same_frontier_baseline = receipt.get("same_frontier_baseline") is True and same_frontier_baseline_schema_ok(points)
same_benchmark = receipt.get("same_benchmark") is True and same_benchmark_schema_ok(points)
same_metric_contract = receipt.get("same_metric_contract") is True and same_metric_contract_schema_ok(points)
rate_formulas_ok = receipt.get("rate_formulas_ok") is True and rate_formulas_schema_ok(points)
strictly_increasing_accumulation = receipt.get("strictly_increasing_accumulation") is True and strictly_increasing_accumulation_schema_ok(points)
margin_growing = receipt.get("margin_growing") is True and margin_growing_schema_ok(points)
curve_verifier_path = receipt.get("curve_verifier_path") if isinstance(receipt.get("curve_verifier_path"), str) else ""
curve_verifier_sha256 = receipt.get("curve_verifier_sha256") if isinstance(receipt.get("curve_verifier_sha256"), str) else ""
round_verifier_path = receipt.get("round_verifier_path") if isinstance(receipt.get("round_verifier_path"), str) else ""
round_verifier_sha256 = receipt.get("round_verifier_sha256") if isinstance(receipt.get("round_verifier_sha256"), str) else ""
current_curve_verifier_sha256 = sha256_file(script_path)
current_round_verifier_sha256 = sha256_file(round_verifier_current_path)
curve_verifier_identity_ok = (
    curve_verifier_path == script_path
    and curve_verifier_sha256 == current_curve_verifier_sha256
)
round_verifier_identity_ok = (
    round_verifier_path == round_verifier_current_path
    and round_verifier_sha256 == current_round_verifier_sha256
)

matches_current = False
stable_projection_matches_current = False
stable_projection_mismatch_paths = []
if schema_ok:
    round_receipt_paths = [point["round_receipt_path"] for point in points]
    with tempfile.TemporaryDirectory() as tmpdir:
        current_path = Path(tmpdir) / "current-curve.json"
        proc = subprocess.run(
            [script_path, "--output", str(current_path), *round_receipt_paths],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if proc.returncode == 0 and current_path.is_file():
            try:
                current = json.loads(current_path.read_text(encoding="utf-8"))
            except Exception:
                current = None
            if isinstance(current, dict):
                stable_projection_mismatch_paths = stable_projection_diff_paths(
                    stable_projection(receipt),
                    stable_projection(current),
                )
                stable_projection_matches_current = not stable_projection_mismatch_paths
                matches_current = stable_projection_matches_current

receipt_ok = schema_ok and matches_current and curve_valid
emit(
    exists=True,
    schema_ok=schema_ok,
    matches_current=matches_current,
    receipt_ok=receipt_ok,
    curve_valid=curve_valid,
    round_count=round_count,
    all_rounds_verified=all_rounds_verified,
    all_rounds_metric_admissible=all_rounds_metric_admissible,
    all_frontier_summaries_verified=all_frontier_summaries_verified,
    same_task_vector=same_task_vector,
    same_frontier_baseline=same_frontier_baseline,
    same_benchmark=same_benchmark,
    same_metric_contract=same_metric_contract,
    rate_formulas_ok=rate_formulas_ok,
    strictly_increasing_accumulation=strictly_increasing_accumulation,
    margin_growing=margin_growing,
    curve_verifier_path=curve_verifier_path,
    curve_verifier_sha256=curve_verifier_sha256,
    curve_verifier_identity_ok=curve_verifier_identity_ok,
    round_verifier_path=round_verifier_path,
    round_verifier_sha256=round_verifier_sha256,
    round_verifier_identity_ok=round_verifier_identity_ok,
    stable_projection_matches_current=stable_projection_matches_current,
    stable_projection_mismatch_count=len(stable_projection_mismatch_paths),
    stable_projection_mismatch_paths=",".join(stable_projection_mismatch_paths),
    schema_issue_count=len(schema_issue_paths),
    schema_issue_paths=",".join(schema_issue_paths),
)
raise SystemExit(0 if receipt_ok else 2)
PYCURVEVERIFY
  exit $?
fi

out_json=""
if [[ "${1:-}" == "--output" ]]; then
  out_json="${2:-}"
  shift 2 || true
fi

"$SWE_PYTHON" - "${BASH_SOURCE[0]}" "$ROUND_VERIFIER" "$out_json" "$@" <<'PYCURVE'
import hashlib
import json
import subprocess
import sys
from pathlib import Path

curve_verifier = sys.argv[1]
round_verifier = sys.argv[2]
out_json = sys.argv[3]
receipt_args = sys.argv[4:]


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_kv(text):
    parsed = {}
    for line in text.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            parsed[key] = value
    return parsed


def bool_text(value):
    return "true" if value else "false"


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def fmt_number(value):
    if value is None:
        return ""
    if isinstance(value, int) and not isinstance(value, bool):
        return str(value)
    if isinstance(value, float):
        return f"{value:.12g}"
    return str(value)


def close(left, right):
    return number(left) and number(right) and abs(float(left) - float(right)) <= 1e-12


curve_verifier_path = str(Path(curve_verifier).resolve())
curve_verifier_sha256 = sha256_file(curve_verifier_path) if Path(curve_verifier_path).is_file() else ""
round_verifier_path = str(Path(round_verifier).resolve())
round_verifier_sha256 = sha256_file(round_verifier_path) if Path(round_verifier_path).is_file() else ""

points = []
verifications = []
all_rounds_verified = bool(receipt_args)
all_rounds_metric_admissible = bool(receipt_args)
all_frontier_summaries_verified = bool(receipt_args)

for raw_path in receipt_args:
    receipt_path = Path(raw_path)
    verify_stdout = ""
    verify_stderr = ""
    verify_rc = 2
    try:
        proc = subprocess.run(
            [round_verifier, "--verify-round-receipt", str(receipt_path)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        verify_stdout = proc.stdout
        verify_stderr = proc.stderr
        verify_rc = proc.returncode
    except Exception as exc:
        verify_stderr = f"{type(exc).__name__}:{exc}"
    verify = parse_kv(verify_stdout)
    round_verified = verify_rc == 0 and verify.get("round_receipt_ok") == "true"
    metric_admissible = verify.get("metric_admissible") == "true"
    frontier_summary_verified = verify.get("frontier_summary_verification_ok") == "true"
    all_rounds_verified = all_rounds_verified and round_verified
    all_rounds_metric_admissible = all_rounds_metric_admissible and metric_admissible
    all_frontier_summaries_verified = all_frontier_summaries_verified and frontier_summary_verified

    try:
        with receipt_path.open(encoding="utf-8") as handle:
            receipt = json.load(handle)
    except Exception:
        receipt = {}
    if not isinstance(receipt, dict):
        receipt = {}

    task_ids = receipt.get("task_ids")
    point = {
        "round_receipt_path": str(receipt_path),
        "round_receipt_sha256": sha256_file(receipt_path) if receipt_path.is_file() else "",
        "round_receipt_ok": round_verified,
        "metric_admissible": metric_admissible,
        "frontier_summary_verification_ok": frontier_summary_verified,
        "run_id": receipt.get("run_id", ""),
        "benchmark_suite": receipt.get("benchmark_suite", ""),
        "benchmark_dataset_name": receipt.get("benchmark_dataset_name", ""),
        "metric_scope": receipt.get("metric_scope", ""),
        "within_task_efficiency_metric_admissible": receipt.get("within_task_efficiency_metric_admissible"),
        "student_model": receipt.get("student_model", ""),
        "selected_task_ids_sha256": receipt.get("selected_task_ids_sha256", ""),
        "task_ids": task_ids if isinstance(task_ids, list) else [],
        "frontier_baseline_sha256": receipt.get("frontier_baseline_sha256", ""),
        "frontier_solve_rate": receipt.get("frontier_solve_rate"),
        "student_solve_rate": receipt.get("student_solve_rate"),
        "elevation_vs_frontier_solve_rate": receipt.get("elevation_vs_frontier_solve_rate"),
        "elevation_vs_frontier": receipt.get("elevation_vs_frontier"),
        "accumulation_index": receipt.get("accumulation_index"),
        "substrate_weight_count": receipt.get("substrate_weight_count"),
    }
    points.append(point)
    verifications.append({
        "round_receipt_path": str(receipt_path),
        "returncode": verify_rc,
        "stdout": verify_stdout,
        "stderr": verify_stderr,
    })

points_sorted = sorted(
    points,
    key=lambda item: (
        item["accumulation_index"] if isinstance(item.get("accumulation_index"), int) and not isinstance(item.get("accumulation_index"), bool) else 10**18,
        item.get("round_receipt_path", ""),
    ),
)

round_count = len(points_sorted)
indices = [p.get("accumulation_index") for p in points_sorted]
rates = [p.get("elevation_vs_frontier_solve_rate") for p in points_sorted]

strictly_increasing_accumulation = (
    round_count >= 2
    and all(isinstance(index, int) and not isinstance(index, bool) for index in indices)
    and all(indices[idx] < indices[idx + 1] for idx in range(round_count - 1))
)
margin_growing = (
    round_count >= 2
    and all(number(rate) for rate in rates)
    and all(float(rates[idx]) < float(rates[idx + 1]) for idx in range(round_count - 1))
)

same_task_vector = False
same_frontier_baseline = False
same_benchmark = False
same_metric_contract = False
rate_formulas_ok = bool(points_sorted)
if points_sorted:
    first = points_sorted[0]
    same_task_vector = all(
        p.get("selected_task_ids_sha256") == first.get("selected_task_ids_sha256")
        and p.get("task_ids") == first.get("task_ids")
        for p in points_sorted
    )
    same_frontier_baseline = all(
        p.get("frontier_baseline_sha256") == first.get("frontier_baseline_sha256")
        and close(p.get("frontier_solve_rate"), first.get("frontier_solve_rate"))
        for p in points_sorted
    )
    same_benchmark = all(
        p.get("benchmark_suite") == "swe_bench_pro"
        and p.get("benchmark_dataset_name") == "ScaleAI/SWE-bench_Pro"
        and p.get("student_model") == "deepseek-v4-pro"
        for p in points_sorted
    )
    same_metric_contract = all(
        p.get("metric_scope") == "paired_frontier_solve_rate_delta"
        and p.get("within_task_efficiency_metric_admissible") is False
        for p in points_sorted
    )
    for p in points_sorted:
        if not close(p.get("elevation_vs_frontier_solve_rate"), float(p.get("student_solve_rate")) - float(p.get("frontier_solve_rate")) if number(p.get("student_solve_rate")) and number(p.get("frontier_solve_rate")) else None):
            rate_formulas_ok = False
            break

curve_valid = (
    round_count >= 2
    and all_rounds_verified
    and all_rounds_metric_admissible
    and all_frontier_summaries_verified
    and same_task_vector
    and same_frontier_baseline
    and same_benchmark
    and same_metric_contract
    and rate_formulas_ok
    and strictly_increasing_accumulation
    and margin_growing
)

receipt = {
    "metric": "pro_elevation_delta_curve",
    "metric_claim": False,
    "curve_valid": curve_valid,
    "round_count": round_count,
    "all_rounds_verified": all_rounds_verified,
    "all_rounds_metric_admissible": all_rounds_metric_admissible,
    "all_frontier_summaries_verified": all_frontier_summaries_verified,
    "curve_verifier_path": curve_verifier_path,
    "curve_verifier_sha256": curve_verifier_sha256,
    "round_verifier_path": round_verifier_path,
    "round_verifier_sha256": round_verifier_sha256,
    "same_task_vector": same_task_vector,
    "same_frontier_baseline": same_frontier_baseline,
    "same_benchmark": same_benchmark,
    "same_metric_contract": same_metric_contract,
    "rate_formulas_ok": rate_formulas_ok,
    "strictly_increasing_accumulation": strictly_increasing_accumulation,
    "margin_growing": margin_growing,
    "accumulation_indices": indices,
    "elevation_vs_frontier_solve_rates": rates,
    "latest_elevation_vs_frontier_solve_rate": rates[-1] if rates else None,
    "points": points_sorted,
    "round_verifications": verifications,
    "no_model_run": True,
    "no_scorer_run": True,
}
if out_json:
    out_path = Path(out_json)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as handle:
        json.dump(receipt, handle, indent=2, sort_keys=True)
        handle.write("\n")

print("metric=pro_elevation_delta_curve")
print("metric_claim=false")
print(f"curve_valid={bool_text(curve_valid)}")
print(f"round_count={round_count}")
print(f"all_rounds_verified={bool_text(all_rounds_verified)}")
print(f"all_rounds_metric_admissible={bool_text(all_rounds_metric_admissible)}")
print(f"all_frontier_summaries_verified={bool_text(all_frontier_summaries_verified)}")
print(f"curve_verifier_path={curve_verifier_path}")
print(f"curve_verifier_sha256={curve_verifier_sha256}")
print(f"round_verifier_path={round_verifier_path}")
print(f"round_verifier_sha256={round_verifier_sha256}")
print(f"same_task_vector={bool_text(same_task_vector)}")
print(f"same_frontier_baseline={bool_text(same_frontier_baseline)}")
print(f"same_benchmark={bool_text(same_benchmark)}")
print(f"same_metric_contract={bool_text(same_metric_contract)}")
print(f"rate_formulas_ok={bool_text(rate_formulas_ok)}")
print(f"strictly_increasing_accumulation={bool_text(strictly_increasing_accumulation)}")
print(f"margin_growing={bool_text(margin_growing)}")
print("accumulation_indices=" + ",".join(fmt_number(index) for index in indices))
print("elevation_vs_frontier_solve_rates=" + ",".join(fmt_number(rate) for rate in rates))
print(f"latest_elevation_vs_frontier_solve_rate={fmt_number(rates[-1] if rates else None)}")
print(f"curve_receipt_path={out_json}")
print("no_model_run=true")
print("no_scorer_run=true")
raise SystemExit(0 if curve_valid else 2)
PYCURVE
