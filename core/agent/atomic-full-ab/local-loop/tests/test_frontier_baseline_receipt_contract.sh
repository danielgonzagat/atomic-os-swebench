#!/usr/bin/env bash
set -euo pipefail

HERE="/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"
cd "$HERE"

FREEZER="$HERE/freeze_frontier_baseline.py"
STREAM="$HERE/run_elevation_stream.sh"
WEIGHTS="$HERE/.corpus/weights.jsonl"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/pred_a.jsonl" <<'JSONL'
{"instance_id":"pro__task-a","model_name_or_path":"frontier-teacher","model_patch":"diff --git a/a.py b/a.py\n"}
JSONL
cat >"$tmp/score_a.log" <<'LOG'
swebench.harness.run_evaluation
Official SWE-bench harness
Instances resolved: 1
LOG
cat >"$tmp/pred_b.jsonl" <<'JSONL'
{"instance_id":"pro__task-b","model_name_or_path":"frontier-teacher","model_patch":""}
JSONL
cat >"$tmp/score_b.log" <<'LOG'
swebench.harness.run_evaluation
Official SWE-bench harness
Instances resolved: 0
LOG

out="$tmp/frontier_baseline.json"
python3 "$FREEZER" \
  --out "$out" \
  --model frontier-teacher \
  --teach-task-id teach__frontier-1 \
  --task pro__task-a "$tmp/pred_a.jsonl" "$tmp/score_a.log" \
  --task pro__task-b "$tmp/pred_b.jsonl" "$tmp/score_b.log" >"$tmp/stdout.jsonl"

test -s "$out"
test -s "$tmp/stdout.jsonl"
python3 - "$out" "$tmp" <<'PY'
import hashlib, json, sys
from pathlib import Path
out = Path(sys.argv[1])
tmp = Path(sys.argv[2])
data = json.loads(out.read_text(encoding="utf-8"))
assert data["metric_claim"] is False
assert data["purpose"] == "frontier_baseline_receipt_not_elevation_result"
assert data["model"] == "frontier-teacher"
assert data["teacher_model"] == "frontier-teacher"
assert data["baseline_role"] == "frontier"
assert data["frontier_baseline"] is True
assert data["frozen"] is True
assert data["official_docker"] is True
assert data["scoring_harness"] == "swebench.harness.run_evaluation"
assert data["benchmark_suite"] == "swe_bench_pro"
assert data["dataset_name"] == "ScaleAI/SWE-bench_Pro"
assert data["dataset_split"] == "test"
assert data["benchmark_label"] == "SWE-bench-Pro"
assert data["atomic"] is True
assert data["teach_task_ids"] == ["teach__frontier-1"]
assert data["task_ids"] == ["pro__task-a", "pro__task-b"]
assert data["instances"] == {"pro__task-a": {"resolved": True}, "pro__task-b": {"resolved": False}}
receipt = data["frontier_receipt"]
assert receipt["format"] == "swebench_pro_frontier_baseline_v1"
assert receipt["task_ids"] == data["task_ids"]
for iid, pred_name, score_name, resolved in [
    ("pro__task-a", "pred_a.jsonl", "score_a.log", True),
    ("pro__task-b", "pred_b.jsonl", "score_b.log", False),
]:
    ev = receipt["evidence"][iid]
    assert ev["resolved"] is resolved
    pred = out.parent / ev["prediction_jsonl"]
    score = out.parent / ev["score_log"]
    assert pred.resolve() == (tmp / pred_name).resolve()
    assert score.resolve() == (tmp / score_name).resolve()
    assert ev["prediction_sha256"] == hashlib.sha256(pred.read_bytes()).hexdigest()
    assert ev["score_log_sha256"] == hashlib.sha256(score.read_bytes()).hexdigest()
PY

selftest="$($STREAM --selftest "$WEIGHTS" "$out" pro__task-a pro__task-b)"
grep -q '^frontier_baseline_paired_tasks=true$' <<<"$selftest"
grep -q '^frontier_baseline_evidence_receipt_ok=true$' <<<"$selftest"
grep -q '^frontier_baseline_provenance_ok=true$' <<<"$selftest"
grep -q '^elevation_valid_if_run=true$' <<<"$selftest"

cat >"$tmp/pred_wrong.jsonl" <<'JSONL'
{"instance_id":"pro__wrong","model_name_or_path":"frontier-teacher","model_patch":""}
JSONL
if python3 "$FREEZER" --out "$tmp/bad_pred.json" --model frontier-teacher --task pro__task-a "$tmp/pred_wrong.jsonl" "$tmp/score_a.log" >"$tmp/bad_pred.out" 2>"$tmp/bad_pred.err"; then
  echo "expected mismatched prediction instance_id to be rejected" >&2
  exit 1
fi
grep -q 'prediction instance_id mismatch' "$tmp/bad_pred.err"

cat >"$tmp/score_ambiguous.log" <<'LOG'
swebench.harness.run_evaluation
Instances resolved: 2
LOG
if python3 "$FREEZER" --out "$tmp/bad_score.json" --model frontier-teacher --task pro__task-a "$tmp/pred_a.jsonl" "$tmp/score_ambiguous.log" >"$tmp/bad_score.out" 2>"$tmp/bad_score.err"; then
  echo "expected non per-task score log to be rejected" >&2
  exit 1
fi
grep -q 'per-task score log must resolve 0 or 1 instances' "$tmp/bad_score.err"

echo "Frontier baseline receipt contract ok"
