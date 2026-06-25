#!/usr/bin/env python3
"""
swe_suite_setup.py - prepare SWE-bench task directories for local A/B and Elevation runs.

Default mode preserves the legacy SWE-bench-Verified setup. Set
ATOMIC_SWE_SUITE_DATASET_NAME=ScaleAI/SWE-bench_Pro to prepare official
SWE-Bench Pro tasks for Elevação.

Env:
  ATOMIC_SWE_SUITE_DATASET_NAME  dataset name (default: princeton-nlp/SWE-bench_Verified)
  ATOMIC_SWE_SUITE_SPLIT         dataset split (default: test)
  ATOMIC_SWE_SUITE_TASKROOT      task directory root (default: ./tasks)
  ATOMIC_SWE_SUITE_ROOT          pristine checkout root (default: /tmp/swe/suite)
  ATOMIC_SWE_SUITE_SKIP_CLONE=1  write task metadata without cloning (contract tests only)

Usage: HF_TOKEN=... python3 swe_suite_setup.py <id1> <id2> ...
Prints a JSON line per instance: {id, repo, base, pristine, taskdir, dataset_name}.
"""
import ast
import json
import os
import subprocess
import sys
from pathlib import Path

try:
    from datasets import load_dataset
except ModuleNotFoundError:
    fallback_python = os.environ.get("SWE_PYTHON", "/opt/homebrew/bin/python3")
    if os.path.exists(fallback_python) and os.path.realpath(fallback_python) != os.path.realpath(sys.executable):
        os.execv(fallback_python, [fallback_python, *sys.argv])
    raise

DEFAULT_DATASET = "princeton-nlp/SWE-bench_Verified"
PRO_DATASET = "ScaleAI/SWE-bench_Pro"

IDS = sys.argv[1:]
assert IDS, "pass instance ids"

DATASET_NAME = os.environ.get("ATOMIC_SWE_SUITE_DATASET_NAME", DEFAULT_DATASET)
DATASET_SPLIT = os.environ.get("ATOMIC_SWE_SUITE_SPLIT", "test")
BENCHMARK_LABEL = os.environ.get("ATOMIC_SWE_SUITE_BENCHMARK_LABEL")
if not BENCHMARK_LABEL:
    if DATASET_NAME == PRO_DATASET:
        BENCHMARK_LABEL = "SWE-bench-Pro"
    elif DATASET_NAME == DEFAULT_DATASET:
        BENCHMARK_LABEL = "SWE-bench-Verified"
    else:
        BENCHMARK_LABEL = DATASET_NAME.replace("/", "__")

TASKROOT = Path(os.environ.get("ATOMIC_SWE_SUITE_TASKROOT", Path(__file__).resolve().parent / "tasks")).resolve()
SUITE = Path(os.environ.get("ATOMIC_SWE_SUITE_ROOT", "/tmp/swe/suite")).resolve()
SKIP_CLONE = os.environ.get("ATOMIC_SWE_SUITE_SKIP_CLONE") == "1"
TASKROOT.mkdir(parents=True, exist_ok=True)
SUITE.mkdir(parents=True, exist_ok=True)


def repo_url(repo: str) -> str:
    return f"https://github.com/{repo}"


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


def first_present(row, *names, default=None):
    for name in names:
        if name in row and row[name] is not None:
            return row[name]
    return default


ds = load_dataset(DATASET_NAME, split=DATASET_SPLIT, token=os.environ.get("HF_TOKEN"))
byid = {r["instance_id"]: r for r in ds}

out = []
for iid in IDS:
    if iid not in byid:
        raise KeyError(f"instance id {iid!r} not found in {DATASET_NAME}:{DATASET_SPLIT}")
    r = byid[iid]
    repo = r["repo"]
    base = r["base_commit"]
    fail_to_pass = json_list(first_present(r, "FAIL_TO_PASS", "fail_to_pass"))
    pass_to_pass = json_list(first_present(r, "PASS_TO_PASS", "pass_to_pass"))
    td = TASKROOT / ("SWE-" + iid)
    (td / ".gold").mkdir(parents=True, exist_ok=True)
    meta = {
        "instance_id": iid,
        "repo": repo,
        "base_commit": base,
        "version": r.get("version"),
        "dataset_name": DATASET_NAME,
        "dataset_split": DATASET_SPLIT,
        "benchmark_label": BENCHMARK_LABEL,
        "FAIL_TO_PASS": fail_to_pass,
        "PASS_TO_PASS": pass_to_pass,
        "fail_to_pass": fail_to_pass,
        "pass_to_pass": pass_to_pass,
    }
    with open(td / "meta.json", "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2, sort_keys=True)
        f.write("\n")
    problem_statement = first_present(r, "problem_statement", "problem", default="")
    (td / "PROBLEM.md").write_text(
        f"# {BENCHMARK_LABEL}: {iid}\n\n"
        f"repo: {repo}  base_commit: {base}\n"
        f"dataset: {DATASET_NAME}  split: {DATASET_SPLIT}\n\n"
        f"## Problem statement\n\n{problem_statement}\n\n"
        "## Instructions (identical for every solver)\n"
        "- Modify ONLY source files to fix the issue.\n"
        "- Do NOT add, modify, or delete any test files - the grader supplies its own tests.\n"
        "- Make the minimal, correct change. When you are done, stop.\n",
        encoding="utf-8",
    )
    (td / ".gold" / "patch.diff").write_text(r.get("patch") or "", encoding="utf-8")
    (td / ".gold" / "test_patch.diff").write_text(r.get("test_patch") or "", encoding="utf-8")

    repo_cache = SUITE / ("_repo_" + repo.replace("/", "__"))
    pristine = SUITE / iid / "pristine"
    if SKIP_CLONE:
        pristine.mkdir(parents=True, exist_ok=True)
    else:
        if not (repo_cache / ".git").exists():
            subprocess.run(["git", "clone", "--quiet", repo_url(repo), str(repo_cache)], check=True)
        if not (pristine / ".git").exists():
            pristine.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["git", "clone", "--quiet", str(repo_cache), str(pristine)], check=True)
        subprocess.run(["git", "-C", str(pristine), "checkout", "--quiet", base], check=True)
    row = {
        "id": iid,
        "repo": repo,
        "base": base,
        "pristine": str(pristine),
        "taskdir": str(td),
        "dataset_name": DATASET_NAME,
        "dataset_split": DATASET_SPLIT,
        "benchmark_label": BENCHMARK_LABEL,
    }
    out.append(row)
    print(json.dumps(row, sort_keys=True), flush=True)

with open(SUITE / "suite.json", "w", encoding="utf-8") as f:
    json.dump(out, f, indent=2, sort_keys=True)
    f.write("\n")
print(f"\nSUITE READY: {len(out)} instances -> {SUITE / 'suite.json'}", file=sys.stderr)
