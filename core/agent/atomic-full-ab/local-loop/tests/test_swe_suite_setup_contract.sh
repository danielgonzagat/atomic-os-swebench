#!/usr/bin/env bash
set -euo pipefail

HERE="/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"
SETUP="$HERE/swe_suite_setup.py"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if /usr/bin/python3 "$SETUP" >"$tmp/no_ids.out" 2>"$tmp/no_ids.err"; then
  echo "expected setup without ids to fail" >&2
  exit 1
fi
grep -q 'pass instance ids' "$tmp/no_ids.err"
if grep -q 'ModuleNotFoundError: No module named' "$tmp/no_ids.err"; then
  echo "setup used a Python without datasets instead of re-execing through SWE_PYTHON" >&2
  exit 1
fi

cat >"$tmp/datasets.py" <<'PY'
def load_dataset(name, split, token=None):
    assert name == "ScaleAI/SWE-bench_Pro", name
    assert split == "test", split
    return [
        {
            "instance_id": "pro__task-1",
            "repo": "owner/repo",
            "base_commit": "abc123",
            "version": "pro-v1",
            "problem_statement": "Fix the Pro issue.",
            "patch": "diff --git a/a.py b/a.py\n",
            "test_patch": "diff --git a/test_a.py b/test_a.py\n",
            "fail_to_pass": "['tests/test_a.py::test_fix']",
            "pass_to_pass": "['tests/test_a.py::test_keep']",
        }
    ]
PY

out="$(
  PYTHONPATH="$tmp" \
  ATOMIC_SWE_SUITE_DATASET_NAME=ScaleAI/SWE-bench_Pro \
  ATOMIC_SWE_SUITE_TASKROOT="$tmp/tasks" \
  ATOMIC_SWE_SUITE_ROOT="$tmp/suite" \
  ATOMIC_SWE_SUITE_SKIP_CLONE=1 \
  python3 "$SETUP" pro__task-1
)"

grep -q '"dataset_name": "ScaleAI/SWE-bench_Pro"' <<<"$out"
grep -q '"id": "pro__task-1"' <<<"$out"

taskdir="$tmp/tasks/SWE-pro__task-1"
grep -q '^# SWE-bench-Pro: pro__task-1$' "$taskdir/PROBLEM.md"
grep -q 'Fix the Pro issue.' "$taskdir/PROBLEM.md"
python3 - "$taskdir/meta.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
assert m["instance_id"] == "pro__task-1"
assert m["dataset_name"] == "ScaleAI/SWE-bench_Pro"
assert m["dataset_split"] == "test"
assert m["benchmark_label"] == "SWE-bench-Pro"
assert m["FAIL_TO_PASS"] == ["tests/test_a.py::test_fix"]
assert m["PASS_TO_PASS"] == ["tests/test_a.py::test_keep"]
PY

test -f "$taskdir/.gold/patch.diff"
test -f "$taskdir/.gold/test_patch.diff"
test -d "$tmp/suite/pro__task-1/pristine"
python3 - "$tmp/suite/suite.json" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
assert rows[0]["dataset_name"] == "ScaleAI/SWE-bench_Pro"
assert rows[0]["benchmark_label"] == "SWE-bench-Pro"
PY

echo "SWE suite setup contract ok"
