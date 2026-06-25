#!/usr/bin/env python3
"""Freeze/import a proof-carrying SWE-Bench Pro frontier baseline receipt.

This tool does not run a model, does not run the SWE-bench scorer, and does not
produce an Elevação number. It only packages already-produced per-task prediction
JSONL files and official score logs into the baseline schema enforced by
run_elevation_stream.sh.
"""
import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path

BENCHMARK_SUITE = "swe_bench_pro"
DATASET_NAME = "ScaleAI/SWE-bench_Pro"
DATASET_SPLIT = "test"
BENCHMARK_LABEL = "SWE-bench-Pro"
SCORING_HARNESS = "swebench.harness.run_evaluation"
RECEIPT_FORMAT = "swebench_pro_frontier_baseline_v1"


def sha256_path(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def relpath(path: Path, base: Path) -> str:
    return os.path.relpath(path.resolve(), base.resolve())


def die(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(2)


def prediction_instance_id(path: Path) -> str:
    if not path.is_file():
        die(f"prediction JSONL not found: {path}")
    ids = []
    try:
        with path.open(encoding="utf-8") as f:
            for line in f:
                if not line.strip():
                    continue
                row = json.loads(line)
                iid = row.get("instance_id") if isinstance(row, dict) else None
                if not isinstance(iid, str) or not iid:
                    die(f"prediction JSONL missing instance_id: {path}")
                ids.append(iid)
    except json.JSONDecodeError as exc:
        die(f"prediction JSONL invalid JSON: {path}: {exc}")
    if len(ids) != 1:
        die(f"per-task prediction JSONL must contain exactly one prediction: {path} count={len(ids)}")
    return ids[0]


def score_resolved(path: Path) -> bool:
    if not path.is_file():
        die(f"score log not found: {path}")
    text = path.read_text(encoding="utf-8", errors="replace")
    matches = re.findall(r"Instances resolved:\s*(\d+)", text)
    if not matches:
        die(f"score log missing 'Instances resolved:' verdict: {path}")
    resolved_count = int(matches[-1])
    if resolved_count not in (0, 1):
        die(f"per-task score log must resolve 0 or 1 instances: {path} resolved={resolved_count}")
    return resolved_count == 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, help="Output baseline JSON path")
    parser.add_argument("--model", required=True, help="Frozen frontier teacher model label")
    parser.add_argument("--teach-task-id", action="append", default=[], help="Disjoint teach task id, repeatable")
    parser.add_argument(
        "--task",
        nargs=3,
        action="append",
        metavar=("INSTANCE_ID", "PREDICTION_JSONL", "SCORE_LOG"),
        required=True,
        help="Per-task evidence triple; repeat once per held-out task",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    out = Path(args.out).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)

    task_ids = [triple[0] for triple in args.task]
    if len(task_ids) != len(set(task_ids)):
        die("duplicate task ids are not a valid paired frontier baseline")
    teach_task_ids = sorted(set(args.teach_task_id))
    overlap = sorted(set(task_ids) & set(teach_task_ids))
    if overlap:
        die(f"teach task ids overlap held-out frontier task ids: {overlap}")

    instances = {}
    evidence = {}
    for iid, pred_raw, score_raw in args.task:
        pred = Path(pred_raw).resolve()
        score = Path(score_raw).resolve()
        predicted_iid = prediction_instance_id(pred)
        if predicted_iid != iid:
            die(f"prediction instance_id mismatch: expected={iid} actual={predicted_iid} path={pred}")
        resolved = score_resolved(score)
        instances[iid] = {"resolved": resolved}
        evidence[iid] = {
            "prediction_jsonl": relpath(pred, out.parent),
            "prediction_sha256": sha256_path(pred),
            "score_log": relpath(score, out.parent),
            "score_log_sha256": sha256_path(score),
            "resolved": resolved,
        }

    data = {
        "metric_claim": False,
        "purpose": "frontier_baseline_receipt_not_elevation_result",
        "model": args.model,
        "teacher_model": args.model,
        "baseline_role": "frontier",
        "frontier_baseline": True,
        "frozen": True,
        "official_docker": True,
        "scoring_harness": SCORING_HARNESS,
        "benchmark_suite": BENCHMARK_SUITE,
        "dataset_name": DATASET_NAME,
        "dataset_split": DATASET_SPLIT,
        "benchmark_label": BENCHMARK_LABEL,
        "task_ids": task_ids,
        "atomic": True,
        "teach_task_ids": teach_task_ids,
        "instances": instances,
        "frontier_receipt": {
            "format": RECEIPT_FORMAT,
            "frozen": True,
            "official_docker": True,
            "scoring_harness": SCORING_HARNESS,
            "benchmark_suite": BENCHMARK_SUITE,
            "dataset_name": DATASET_NAME,
            "dataset_split": DATASET_SPLIT,
            "benchmark_label": BENCHMARK_LABEL,
            "task_ids": task_ids,
            "evidence": evidence,
        },
    }
    out.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"ok": True, "baseline": str(out), "task_ids": task_ids, "resolved_count": sum(1 for row in instances.values() if row["resolved"])}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
