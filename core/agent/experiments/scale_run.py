#!/usr/bin/env python3
"""
Scale the atomic AGENTIC loop across multiple SWE-bench instances (pytest-based,
light-dep repos). For each instance: set up a real env (clone @ base_commit, venv,
spec install), apply+commit the test_patch (so FAIL_TO_PASS exists but is hidden
from the agent), run swe_agent.py, collect the prediction. Then eval all via the
official harness (separately).

Usage: DEEPSEEK_API_KEY env set; python3 scale_run.py --ids-file ids_scale.txt --out preds-agent-scale.jsonl
"""
import json, os, subprocess, argparse, shlex, re
from pathlib import Path
from datasets import load_dataset
from swebench.harness.constants import MAP_REPO_VERSION_TO_SPECS

CACHE = Path.home() / ".swebench-repo-cache"
WORK = Path("/Users/danielpenin/swebench-atomic-ab/scale-work")
AGENT = "/Users/danielpenin/swebench-atomic-ab/swe_agent.py"


def sh(cmd, cwd=None, timeout=1800, check=False):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout, shell=isinstance(cmd, str), check=check)


def setup(inst):
    iid = inst["instance_id"]; repo = inst["repo"]; base = inst["base_commit"]
    spec = MAP_REPO_VERSION_TO_SPECS[repo][inst["version"]]
    cache = CACHE / repo.replace("/", "__")
    if not cache.exists():
        sh(["git", "clone", f"https://github.com/{repo}.git", str(cache)], timeout=1800, check=True)
    wd = WORK / iid
    if wd.exists():
        sh(["rm", "-rf", str(wd)])
    WORK.mkdir(parents=True, exist_ok=True)
    sh(["git", "clone", str(cache), str(wd)], check=True)
    r = sh(["git", "checkout", base], cwd=wd)
    if r.returncode != 0:
        sh(["git", "fetch", "origin", base], cwd=cache, timeout=900)
        sh(["git", "fetch", str(cache)], cwd=wd, timeout=300)
        sh(["git", "checkout", base], cwd=wd, check=True)
    # venv + install (use the system python; spec python is for the docker conda env)
    sh(["python3", "-m", "venv", ".venv"], cwd=wd, check=True)
    py = str(wd / ".venv/bin/python")
    sh([py, "-m", "pip", "install", "-q", "-U", "pip", "setuptools", "wheel"], cwd=wd)
    install = spec.get("install", "pip install -e .")
    # normalize the spec install to use the venv pip
    install = install.replace("pip install", f"{py} -m pip install").replace("python -m pip", f"{py} -m pip")
    if "setup.py" in install:
        install = install.replace("python ", f"{py} ")
    ri = sh(install, cwd=wd, timeout=2400)
    sh([py, "-m", "pip", "install", "-q", "pytest"], cwd=wd)
    for pkg in (spec.get("pip_packages") or []):
        sh([py, "-m", "pip", "install", "-q", pkg], cwd=wd)
    # apply test_patch + commit (so FAIL_TO_PASS tests exist; not in the prediction diff)
    (wd / "_tp.diff").write_text(inst["test_patch"])
    rtp = sh(["git", "apply", "_tp.diff"], cwd=wd)
    if rtp.returncode != 0:
        rtp = sh(["git", "apply", "--3way", "_tp.diff"], cwd=wd)
    sh(["git", "add", "-A"], cwd=wd)
    sh(["git", "-c", "user.email=a@b.c", "-c", "user.name=agent", "commit", "-q", "-m", "tp"], cwd=wd)
    # build agent test cmd: run the FAIL_TO_PASS tests via pytest
    f2p = json.loads(inst["FAIL_TO_PASS"]) if isinstance(inst["FAIL_TO_PASS"], str) else inst["FAIL_TO_PASS"]
    test_files = re.findall(r'(?m)^\+\+\+ b/(\S+)', inst["test_patch"])
    quoted = " ".join(shlex.quote(t) for t in f2p[:8])
    test_cmd = f".venv/bin/python -m pytest -q {quoted}"
    return wd, test_cmd, test_files, (ri.returncode == 0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ids-file", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--max-steps", type=int, default=20)
    args = ap.parse_args()
    want = [l.strip() for l in Path(args.ids_file).read_text().splitlines() if l.strip()]
    ds = load_dataset("princeton-nlp/SWE-bench_Verified", split="test")
    by_id = {r["instance_id"]: dict(r) for r in ds if r["instance_id"] in set(want)}
    preds = []
    for iid in want:
        inst = by_id.get(iid)
        if not inst:
            print(f"!! {iid} not in dataset"); continue
        print(f"\n########## {iid} ({inst['repo']}) ##########")
        try:
            wd, test_cmd, test_files, ok = setup(inst)
            print(f"  env ready (install_ok={ok}); test_cmd={test_cmd[:70]}")
        except Exception as e:
            print(f"  SETUP FAILED: {str(e)[:160]}")
            preds.append({"instance_id": iid, "model_patch": "", "model_name_or_path": "atomic-agent-deepseek-v4-pro"})
            continue
        (wd / "_issue.txt").write_text(inst["problem_statement"])
        block = ",".join(test_files) or "tests/"
        cmd = ["python3", "-u", AGENT, "--instance", iid, "--repo-dir", str(wd),
               "--test-cmd", test_cmd, "--issue-file", str(wd / "_issue.txt"),
               "--block", block, "--max-steps", str(args.max_steps), "--out", str(wd / "_pred.jsonl")]
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
        print(r.stdout[-400:])
        try:
            p = json.loads((wd / "_pred.jsonl").read_text())
        except Exception:
            p = {"instance_id": iid, "model_patch": "", "model_name_or_path": "atomic-agent-deepseek-v4-pro"}
        preds.append({k: p.get(k) for k in ["instance_id", "model_patch", "model_name_or_path"]})
    with open(args.out, "w") as f:
        for p in preds:
            f.write(json.dumps(p) + "\n")
    print(f"\n=== wrote {len(preds)} predictions to {args.out} ===")


if __name__ == "__main__":
    main()
