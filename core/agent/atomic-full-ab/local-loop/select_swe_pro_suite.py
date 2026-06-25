#!/usr/bin/env python3
"""Select a deterministic held-out SWE-Bench Pro task manifest.

This is setup/provenance only. It never emits problem statements, gold patches, or
any Elevação number.
"""
import ast
import hashlib
import json
import os
import sys
from collections import Counter
from pathlib import Path

try:
    from datasets import load_dataset
except ModuleNotFoundError:
    fallback_python = os.environ.get("SWE_PYTHON", "/opt/homebrew/bin/python3")
    if os.path.exists(fallback_python) and os.path.realpath(fallback_python) != os.path.realpath(sys.executable):
        os.execv(fallback_python, [fallback_python, *sys.argv])
    raise

DATASET_NAME = os.environ.get("ATOMIC_SWE_PRO_SELECTION_DATASET_NAME", "ScaleAI/SWE-bench_Pro")
DATASET_SPLIT = os.environ.get("ATOMIC_SWE_PRO_SELECTION_SPLIT", "test")
BENCHMARK_SUITE = "swe_bench_pro"
BENCHMARK_LABEL = "SWE-bench-Pro"
SEED = os.environ.get("ATOMIC_SWE_PRO_SELECTION_SEED", "atomic-elevation-pro-v1")
COUNT = int(os.environ.get("ATOMIC_SWE_PRO_SELECTION_COUNT", "5"))
OUT = Path(os.environ.get(
    "ATOMIC_SWE_PRO_SELECTION_OUT",
    Path(__file__).resolve().parent / "elevation_pro_suite_manifest.json",
)).resolve()
TEACH_IDS = sorted({x.strip() for x in os.environ.get("ATOMIC_SWE_PRO_SELECTION_TEACH_IDS", "").split(",") if x.strip()})

if COUNT <= 0:
    raise SystemExit("ATOMIC_SWE_PRO_SELECTION_COUNT must be positive")
if DATASET_NAME != "ScaleAI/SWE-bench_Pro" or DATASET_SPLIT != "test":
    raise SystemExit(f"official SWE-Bench Pro test split required, got {DATASET_NAME}:{DATASET_SPLIT}")


def json_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return value
    if isinstance(value, tuple):
        return list(value)
    if isinstance(value, str):
        stripped = value.strip()
        if not stripped:
            return []
        try:
            parsed = json.loads(stripped)
        except json.JSONDecodeError:
            try:
                parsed = ast.literal_eval(stripped)
            except (ValueError, SyntaxError):
                parsed = stripped
        return parsed if isinstance(parsed, list) else [parsed]
    try:
        return list(value)
    except TypeError:
        return [value]


def rank(instance_id: str) -> str:
    return hashlib.sha256((SEED + "\0" + instance_id).encode("utf-8")).hexdigest()


def public_row(row):
    fail_to_pass = json_list(row.get("fail_to_pass") or row.get("FAIL_TO_PASS"))
    pass_to_pass = json_list(row.get("pass_to_pass") or row.get("PASS_TO_PASS"))
    return {
        "instance_id": row["instance_id"],
        "repo": row.get("repo"),
        "base_commit": row.get("base_commit"),
        "repo_language": row.get("repo_language"),
        "dockerhub_tag": row.get("dockerhub_tag"),
        "issue_specificity": row.get("issue_specificity"),
        "issue_categories": json_list(row.get("issue_categories")),
        "fail_to_pass_count": len(fail_to_pass),
        "pass_to_pass_count": len(pass_to_pass),
        "selection_rank_sha256": rank(row["instance_id"]),
    }


def main() -> int:
    rows = list(load_dataset(DATASET_NAME, split=DATASET_SPLIT, token=os.environ.get("HF_TOKEN")))
    teach = set(TEACH_IDS)
    eligible = [r for r in rows if r["instance_id"] not in teach]
    if len(eligible) < COUNT:
        raise SystemExit(f"not enough eligible tasks: requested={COUNT} eligible={len(eligible)}")
    selected = sorted(eligible, key=lambda r: (rank(r["instance_id"]), r["instance_id"]))[:COUNT]
    selected_ids = [r["instance_id"] for r in selected]
    data = {
        "metric_claim": False,
        "purpose": "held_out_candidate_manifest_not_elevation_result",
        "official_benchmark": True,
        "benchmark_suite": BENCHMARK_SUITE,
        "dataset_name": DATASET_NAME,
        "dataset_split": DATASET_SPLIT,
        "benchmark_label": BENCHMARK_LABEL,
        "selection_method": "sha256(seed + NUL + instance_id) over official dataset rows; excludes teach task ids",
        "selection_seed": SEED,
        "total_count": len(rows),
        "eligible_count": len(eligible),
        "selected_count": len(selected),
        "teach_task_ids": TEACH_IDS,
        "selected_task_ids": selected_ids,
        "repo_language_distribution": dict(sorted(Counter(r.get("repo_language") or "unknown" for r in rows).items())),
        "selected_repo_language_distribution": dict(sorted(Counter(r.get("repo_language") or "unknown" for r in selected).items())),
        "rows": [public_row(r) for r in selected],
        "anti_leakage": {
            "problem_statement": "omitted",
            "patch": "omitted",
            "test_patch": "omitted",
        },
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"ok": True, "manifest": str(OUT), "selected_task_ids": selected_ids}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
