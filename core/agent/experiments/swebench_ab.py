#!/usr/bin/env python3
"""
Controlled atomic ON/OFF A/B for SWE-bench Verified — attributable, leak-free.

Both arms are IDENTICAL except the edit mechanism:
  - same model (deepseek-v4-pro), same temperature, same max_tokens
  - same context gathering (gather_files), same issue-only prompt
  - NO test-name leak (FAIL_TO_PASS/PASS_TO_PASS never shown), NO hints_text

  ON  (atomic): LLM outputs FILE + LINE RANGE + NEW CODE. System reads the ACTUAL
                bytes at those lines (ground truth, no hallucinated old-text),
                applies the edit, syntax-validates (compile()), then git produces
                the diff.
  OFF (raw):    LLM outputs a unified diff directly (must hallucinate the context
                lines); used as-is. No read-real-bytes, no syntax validation.

Scoring is done OUT OF BAND by the official harness (FAIL_TO_PASS + PASS_TO_PASS
in isolated containers). This script only produces predictions.jsonl.

Usage:
  DEEPSEEK_MODEL=deepseek-v4-pro python3 swebench_ab.py --mode atomic --instances-file ids.txt --output preds-on.jsonl
  DEEPSEEK_MODEL=deepseek-v4-pro python3 swebench_ab.py --mode raw    --instances-file ids.txt --output preds-off.jsonl
"""
import json, os, time, subprocess, tempfile, re, argparse
from pathlib import Path
from typing import Optional

API_KEY = os.environ.get("DEEPSEEK_API_KEY", "")
MODEL = os.environ.get("DEEPSEEK_MODEL", "deepseek-v4-pro")


def call_deepseek(messages, max_tokens=6000) -> str:
    import urllib.request
    if not API_KEY:
        raise RuntimeError("DEEPSEEK_API_KEY required")
    d = json.dumps({"model": MODEL, "messages": messages, "temperature": 0,
                    "max_tokens": max_tokens}).encode()
    r = urllib.request.Request("https://api.deepseek.com/v1/chat/completions", data=d,
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {API_KEY}"})
    with urllib.request.urlopen(r, timeout=300) as resp:
        return json.loads(resp.read())["choices"][0]["message"]["content"]


REPO_CACHE = Path.home() / ".swebench-repo-cache"


def clone_repo(repo_name: str, base_commit: str, work_dir: Path) -> Path:
    """Cache a full clone per repo (once), then fast local clones per instance."""
    cache = REPO_CACHE / repo_name.replace("/", "__")
    if not cache.exists():
        REPO_CACHE.mkdir(parents=True, exist_ok=True)
        r = subprocess.run(["git", "clone", f"https://github.com/{repo_name}.git", str(cache)],
                           capture_output=True, text=True, timeout=1200)
        if r.returncode != 0:
            raise RuntimeError(f"Cache clone failed: {r.stderr[:300]}")
    repo_path = work_dir / repo_name.split("/")[-1]
    r = subprocess.run(["git", "clone", str(cache), str(repo_path)],
                       capture_output=True, text=True, timeout=180)
    if r.returncode != 0:
        raise RuntimeError(f"Local clone failed: {r.stderr[:300]}")
    r = subprocess.run(["git", "-C", str(repo_path), "checkout", base_commit],
                       capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        subprocess.run(["git", "-C", str(cache), "fetch", "origin", "--tags"], capture_output=True, timeout=600)
        subprocess.run(["git", "-C", str(repo_path), "fetch", str(cache)], capture_output=True, timeout=180)
        r = subprocess.run(["git", "-C", str(repo_path), "checkout", base_commit],
                           capture_output=True, text=True, timeout=60)
        if r.returncode != 0:
            raise RuntimeError(f"Checkout {base_commit[:8]} failed: {r.stderr[:200]}")
    return repo_path


def _merge(regions):
    regions = sorted(regions)
    out = []
    for s, e in regions:
        if out and s <= out[-1][1] + 6:
            out[-1] = (out[-1][0], max(out[-1][1], e))
        else:
            out.append((s, e))
    return out


def gather_files(repo_path: Path, issue: str, max_files: int = 8, radius: int = 40) -> str:
    """IDENTICAL context for both arms: show the RELEVANT regions (around keyword
    hits) of relevant .py files, with REAL line numbers — so the model edits code
    it can actually see, not head/tail of huge files."""
    keywords = re.findall(r'\b[a-zA-Z_][a-zA-Z0-9_\.]{3,}\b', issue.lower())
    stop = {'the','and','for','this','that','with','from','when','not','are','was','has',
            'have','its','into','will','can','been','which','should','would','could','does',
            'code','file','function','example','following','using','model','models','data',
            'also','because','like','make','need','only','each','how','your','more','some',
            'add','new','current','work','see','use','after','before','first','then','here',
            'there','about','other','these','those','such','than','still','well','between'}
    keywords = [w for w in keywords if w not in stop][:15]
    hits: dict = {}  # file -> set(line numbers)
    for kw in keywords[:8]:
        try:
            r = subprocess.run(["grep", "-rn", "--include=*.py", kw, str(repo_path)],
                               capture_output=True, text=True, timeout=25)
            for line in r.stdout.split("\n"):
                m = re.match(r'^([^:]+):(\d+):', line)
                if m:
                    hits.setdefault(m.group(1), set()).add(int(m.group(2)))
        except Exception:
            pass
    # rank files by number of keyword hits (most relevant first)
    ranked = sorted(hits.items(), key=lambda kv: -len(kv[1]))[:max_files]
    context = ""
    for fpath, linenos in ranked:
        try:
            src = Path(fpath).read_text().split("\n")
            rel = str(Path(fpath).relative_to(repo_path))
            total = len(src)
            regions = _merge([(max(1, n - radius), min(total, n + radius)) for n in sorted(linenos)])[:4]
            block = f"\n=== {rel} ({total} lines) ===\n"
            for s, e in regions:
                block += f"  --- lines {s}-{e} ---\n"
                block += "\n".join(f"{i:5d}| {src[i-1]}" for i in range(s, e + 1)) + "\n"
            context += block[:7000]
        except Exception:
            pass
    return context


def apply_line_edit(repo_path: Path, file_rel: str, start_line: int, end_line: int, new_code: str) -> dict:
    fp = repo_path / file_rel
    if not fp.exists():
        return {"ok": False, "error": f"File not found: {file_rel}"}
    lines = fp.read_text().split("\n")
    if start_line < 1 or end_line > len(lines):
        return {"ok": False, "error": f"Line range out of bounds"}
    new_lines = lines[:start_line - 1] + new_code.split("\n") + lines[end_line:]
    new_content = "\n".join(new_lines)
    if file_rel.endswith(".py"):
        try:
            compile(new_content, file_rel, "exec")
        except SyntaxError as e:
            return {"ok": False, "error": f"Syntax error: {e}"}  # atomic REFUSES
    fp.write_text(new_content)
    return {"ok": True}


ATOMIC_SYSTEM = """You are an expert software engineer. Identify the EXACT line changes needed to fix a bug.

For each change, output:

FILE: path/to/file.py
LINES: start-end
NEW CODE:
```python
replacement lines (keep the same indentation as the original)
```

RULES:
1. Reference line numbers from the context provided (left column).
2. Make MINIMAL changes — only what's needed.
3. Preserve EXACT indentation.
4. To insert after line N without removing, use range "N-N".
5. Include all necessary imports.
6. Output ALL needed changes in ONE response."""

RAW_SYSTEM = """You are an expert software engineer. Produce a patch that fixes the bug.

RULES:
1. Read the context carefully (line numbers are in the left column).
2. Make MINIMAL changes — only what's needed.
3. Your response must be a VALID unified diff in git format.
4. Include the complete file path in each diff header (a/path and b/path).
5. Each hunk must have correct @@ line numbers and surrounding context lines.
6. Include all necessary imports."""


def gen_atomic(instance: dict, work_dir: Path) -> Optional[str]:
    repo_path = clone_repo(instance["repo"], instance["base_commit"], work_dir)
    context = gather_files(repo_path, instance["problem_statement"])
    user = f"ISSUE:\n{instance['problem_statement'][:4000]}\n\nCODEBASE (line numbers in left column):\n{context[:12000]}\n\nIdentify the file(s), line range(s), and new code needed to fix this issue."
    raw = call_deepseek([{"role": "system", "content": ATOMIC_SYSTEM}, {"role": "user", "content": user}])
    applied = 0
    for block in re.split(r'\n(?=FILE:)', raw):
        fm = re.match(r'FILE:\s*(\S+)', block)
        lm = re.search(r'LINES:\s*(\d+)\s*-\s*(\d+)', block)
        cm = re.search(r'NEW CODE:\s*\n```(?:python)?\s*\n(.*?)\n```', block, re.DOTALL)
        if not fm or not lm:
            continue
        res = apply_line_edit(repo_path, fm.group(1).strip(), int(lm.group(1)), int(lm.group(2)),
                              cm.group(1) if cm else "")
        if res["ok"]:
            applied += 1
    if applied == 0:
        return None
    subprocess.run(["git", "-C", str(repo_path), "add", "-A"], capture_output=True, timeout=10)
    r = subprocess.run(["git", "-C", str(repo_path), "diff", "--cached", instance["base_commit"]],
                       capture_output=True, text=True, timeout=15)
    return r.stdout.strip() or None


def gen_raw(instance: dict, work_dir: Path) -> Optional[str]:
    repo_path = clone_repo(instance["repo"], instance["base_commit"], work_dir)
    context = gather_files(repo_path, instance["problem_statement"])  # IDENTICAL context
    user = f"ISSUE:\n{instance['problem_statement'][:4000]}\n\nCODEBASE (line numbers in left column):\n{context[:12000]}\n\nReturn ONLY the unified diff (git diff format). Start your response with: diff --git"
    raw = call_deepseek([{"role": "system", "content": RAW_SYSTEM}, {"role": "user", "content": user}])
    i = raw.find("diff --git")
    patch = raw[i:] if i >= 0 else raw
    return patch.strip() or None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["atomic", "raw"], required=True)
    ap.add_argument("--dataset", default="princeton-nlp/SWE-bench_Verified")
    ap.add_argument("--split", default="test")
    ap.add_argument("--instances-file", required=True, help="newline-separated instance_ids")
    ap.add_argument("--output", required=True)
    ap.add_argument("--model-name", default=None)
    args = ap.parse_args()

    from datasets import load_dataset
    want = [l.strip() for l in Path(args.instances_file).read_text().splitlines() if l.strip()]
    ds = load_dataset(args.dataset, split=args.split)
    by_id = {r["instance_id"]: dict(r) for r in ds if r["instance_id"] in set(want)}
    instances = [by_id[i] for i in want if i in by_id]
    model_name = args.model_name or f"atomic-ab-{args.mode}-deepseek-v4-pro"

    print(f"=== mode={args.mode}  model={MODEL}  instances={len(instances)} ===")
    gen = gen_atomic if args.mode == "atomic" else gen_raw
    preds, ok = [], 0
    for k, inst in enumerate(instances, 1):
        iid = inst["instance_id"]
        t0 = time.time()
        try:
            with tempfile.TemporaryDirectory(prefix=f"swe-{iid[:18]}-") as wd:
                patch = gen(inst, Path(wd))
        except Exception as e:
            print(f"  [{k}/{len(instances)}] {iid}  ERROR: {str(e)[:120]}")
            patch = None
        ok += 1 if patch else 0
        print(f"  [{k}/{len(instances)}] {iid}  patch={'OK '+str(len(patch))+'ch' if patch else 'NONE'}  {time.time()-t0:.0f}s")
        preds.append({"instance_id": iid, "model_patch": patch or "", "model_name_or_path": model_name})

    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w") as f:
        for p in preds:
            f.write(json.dumps(p) + "\n")
    print(f"=== {args.mode}: {ok}/{len(preds)} non-empty patches -> {args.output} ===")


if __name__ == "__main__":
    main()
