#!/usr/bin/env bash
set -euo pipefail

HERE="/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"
SELECTOR="$HERE/select_swe_pro_suite.py"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/datasets.py" <<'PY'
def load_dataset(name, split, token=None):
    assert name == "ScaleAI/SWE-bench_Pro", name
    assert split == "test", split
    return [
        {
            "instance_id": "pro__task-a",
            "repo": "owner/a",
            "base_commit": "aaa111",
            "repo_language": "python",
            "dockerhub_tag": "img-a",
            "issue_specificity": "high",
            "issue_categories": ["bug"],
            "fail_to_pass": ["tests/test_a.py::test_fix"],
            "pass_to_pass": ["tests/test_a.py::test_keep"],
            "problem_statement": "must not leak",
            "patch": "must not leak",
            "test_patch": "must not leak",
        },
        {
            "instance_id": "pro__task-b",
            "repo": "owner/b",
            "base_commit": "bbb222",
            "repo_language": "go",
            "dockerhub_tag": "img-b",
            "issue_specificity": "medium",
            "issue_categories": '["bug", "api"]',
            "fail_to_pass": "['tests/test_b.py::test_fix', 'tests/test_b.py::test_other']",
            "pass_to_pass": "['tests/test_b.py::test_keep']",
            "problem_statement": "must not leak",
            "patch": "must not leak",
            "test_patch": "must not leak",
        },
        {
            "instance_id": "pro__task-c",
            "repo": "owner/c",
            "base_commit": "ccc333",
            "repo_language": "js",
            "dockerhub_tag": "img-c",
            "issue_specificity": "low",
            "issue_categories": '["front_end_knowledge"]',
            "fail_to_pass": "['x']",
            "pass_to_pass": "['y', 'z']",
            "problem_statement": "must not leak",
            "patch": "must not leak",
            "test_patch": "must not leak",
        },
        {
            "instance_id": "pro__task-d",
            "repo": "owner/d",
            "base_commit": "ddd444",
            "repo_language": "ts",
            "dockerhub_tag": "img-d",
            "issue_specificity": "low",
            "issue_categories": [],
            "fail_to_pass": ["x"],
            "pass_to_pass": [],
            "problem_statement": "must not leak",
            "patch": "must not leak",
            "test_patch": "must not leak",
        },
    ]
PY

out="$tmp/manifest.json"
PYTHONPATH="$tmp" \
ATOMIC_SWE_PRO_SELECTION_COUNT=3 \
ATOMIC_SWE_PRO_SELECTION_SEED=contract-seed \
ATOMIC_SWE_PRO_SELECTION_TEACH_IDS=pro__task-b \
ATOMIC_SWE_PRO_SELECTION_OUT="$out" \
python3 "$SELECTOR" >"$tmp/stdout.jsonl"

test -s "$out"
test -s "$tmp/stdout.jsonl"
python3 - "$out" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
assert m["metric_claim"] is False
assert m["official_benchmark"] is True
assert m["benchmark_suite"] == "swe_bench_pro"
assert m["dataset_name"] == "ScaleAI/SWE-bench_Pro"
assert m["dataset_split"] == "test"
assert m["benchmark_label"] == "SWE-bench-Pro"
assert m["selection_seed"] == "contract-seed"
assert "sha256" in m["selection_method"]
assert m["total_count"] == 4
assert m["eligible_count"] == 3
assert m["selected_count"] == 3
assert m["teach_task_ids"] == ["pro__task-b"]
assert "pro__task-b" not in m["selected_task_ids"]
assert len(m["selected_task_ids"]) == len(set(m["selected_task_ids"])) == 3
assert [r["instance_id"] for r in m["rows"]] == m["selected_task_ids"]
for row in m["rows"]:
    assert "problem_statement" not in row
    assert "patch" not in row
    assert "test_patch" not in row
    assert set(["instance_id", "repo", "base_commit", "repo_language", "dockerhub_tag", "fail_to_pass_count", "pass_to_pass_count"]).issubset(row)
PY

out2="$tmp/manifest2.json"
PYTHONPATH="$tmp" \
ATOMIC_SWE_PRO_SELECTION_COUNT=3 \
ATOMIC_SWE_PRO_SELECTION_SEED=contract-seed \
ATOMIC_SWE_PRO_SELECTION_TEACH_IDS=pro__task-b \
ATOMIC_SWE_PRO_SELECTION_OUT="$out2" \
python3 "$SELECTOR" >/dev/null
cmp "$out" "$out2"

echo "SWE Pro selection contract ok"
