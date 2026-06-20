#!/usr/bin/env python3
"""
swe_suite_setup.py — prepare a suite of SWE-bench-Verified instances for the local A/B.

For each instance id: pull from princeton-nlp/SWE-bench_Verified, write a task dir
(PROBLEM.md shown to arms with identical source-only scope; meta.json; .gold/ gate-only),
and clone+checkout the repo at base_commit into /tmp/swe/suite/<id>/pristine.

Usage: HF_TOKEN=... python3 swe_suite_setup.py <id1> <id2> ...
Prints a JSON line per instance: {id, repo, base, pristine, taskdir}.
"""
import os, sys, json, subprocess
from pathlib import Path
from datasets import load_dataset

IDS = sys.argv[1:]
assert IDS, "pass instance ids"
TASKROOT = Path(__file__).resolve().parent / "tasks"
SUITE = Path("/tmp/swe/suite")
SUITE.mkdir(parents=True, exist_ok=True)

ds = load_dataset("princeton-nlp/SWE-bench_Verified", split="test", token=os.environ.get("HF_TOKEN"))
byid = {r["instance_id"]: r for r in ds}

REPO_URL = lambda repo: f"https://github.com/{repo}"

out = []
for iid in IDS:
    r = byid[iid]
    repo, base = r["repo"], r["base_commit"]
    td = TASKROOT / ("SWE-" + iid)
    (td / ".gold").mkdir(parents=True, exist_ok=True)
    json.dump({"instance_id": iid, "repo": repo, "base_commit": base, "version": r.get("version"),
               "FAIL_TO_PASS": json.loads(r["FAIL_TO_PASS"]), "PASS_TO_PASS": json.loads(r["PASS_TO_PASS"])},
              open(td / "meta.json", "w"), indent=2)
    (td / "PROBLEM.md").write_text(
        f"# SWE-bench-Verified: {iid}\n\nrepo: {repo}  base_commit: {base}\n\n"
        f"## Problem statement\n\n{r['problem_statement']}\n\n"
        "## Instructions (identical for every solver)\n"
        "- Modify ONLY source files to fix the issue.\n"
        "- Do NOT add, modify, or delete any test files — the grader supplies its own tests.\n"
        "- Make the minimal, correct change. When you are done, stop.\n")
    (td / ".gold" / "patch.diff").write_text(r["patch"])
    (td / ".gold" / "test_patch.diff").write_text(r["test_patch"])

    # clone (cache per-repo bare-ish) + checkout pristine
    repo_cache = SUITE / ("_repo_" + repo.replace("/", "__"))
    if not (repo_cache / ".git").exists():
        subprocess.run(["git", "clone", "--quiet", REPO_URL(repo), str(repo_cache)], check=True)
    pristine = SUITE / iid / "pristine"
    if not (pristine / ".git").exists():
        pristine.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "clone", "--quiet", str(repo_cache), str(pristine)], check=True)
    subprocess.run(["git", "-C", str(pristine), "checkout", "--quiet", base], check=True)
    out.append({"id": iid, "repo": repo, "base": base, "pristine": str(pristine), "taskdir": str(td)})
    print(json.dumps(out[-1]), flush=True)

json.dump(out, open(SUITE / "suite.json", "w"), indent=2)
print(f"\nSUITE READY: {len(out)} instances -> {SUITE/'suite.json'}", file=sys.stderr)
