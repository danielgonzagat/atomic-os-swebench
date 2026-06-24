#!/usr/bin/env python3
"""LIVE within-task convergence-by-elimination harness (the doctrine's §5 weak form, the ONE untested path to
'Atomic modelo fixo superar baseline'). Model-free SUBSTRATE logic; the fixed student model is DeepSeek V4 Pro
(required). NON-CIRCULAR: travas list proven-WRONG diffs to AVOID; the gold/correct diff is NEVER shown.

Edits ZERO co-owned files: the trava is injected purely via the driver's EXISTING `--task <file>` interface
(an augmented PROBLEM.md). Scoring is the OFFICIAL SWE-bench Docker harness (FAIL_TO_PASS+PASS_TO_PASS), never
self-graded.

THE BY-NUMBER QUESTION (apples-to-apples, isolates the elimination VALUE, not just 'more attempts'):
  does SEQUENTIAL re-fire WITH elimination resolve MORE tasks than BEST-OF-K INDEPENDENT one-shots (same budget)?
  If yes -> the substrate's weak-form elimination makes the fixed model surpass its own one-shot baseline, by number.

Run:  DEEPSEEK_API_KEY=... DEEPSEEK_MODEL=deepseek-v4-pro python3 refire_elimination.py TASK_IDS... [--k 6]
Without a key it EXITS CLEANLY (honest 'blocked'), and `--selftest` validates the scoring plumbing via a positive
control (gold patch must score resolved=1) + negative control (empty diff resolved=0), proving correctness up to
the model boundary.
"""
import argparse, json, os, re, subprocess, sys, shutil, hashlib

# NETWORK-FREE instances only: the sandboxed Docker eval has no reliable external network, so instances whose
# FAIL_TO_PASS hits live services (the `requests` suite: httpbin/503/JSONDecodeError) give FALSE NEGATIVES.
# Validated by selftest: psf__requests-1921 gold -> unresolved (network), pytest-dev__pytest-7982 gold -> resolved.
# Recommended live set = multi-attempt bugs (heavy re-fire churn, where elimination has the most purchase) that are
# deterministic/offline. pylint-4661 (78 attempts, first resolve @#70) is the marquee case for the weak form.
RECOMMENDED_TASKS = [
    "pylint-dev__pylint-4661", "pylint-dev__pylint-6528", "django__django-11490",
    "pytest-dev__pytest-7982", "pytest-dev__pytest-5262", "sympy__sympy-13877",
]
HERE = os.path.dirname(os.path.abspath(__file__))
LOOP = os.path.abspath(os.path.join(HERE, "..", ".."))          # .../local-loop
DRIVER = os.path.join(LOOP, "local_atomic_agent.py")
CORPUS = os.path.join(LOOP, ".corpus", "weights.jsonl")
PARQUET = ("/Users/danielpenin/.cache/huggingface/hub/datasets--princeton-nlp--SWE-bench_Verified/"
           "snapshots/c104f840cc67f8b6eec6f759ebc8b2693d585d4a/data/test-00000-of-00001.parquet")
WORKROOT = "/private/tmp/swe/refire"
SUITE = "/private/tmp/swe/suite"   # pristine per-task checkouts (reused from prior runs if present)


def gold_for(iids):
    import pandas as pd
    df = pd.read_parquet(PARQUET, columns=["instance_id", "patch", "problem_statement"])
    return {r.instance_id: {"patch": r.patch, "problem": r.problem_statement}
            for r in df.itertuples() if r.instance_id in set(iids)}


def render_trava_addendum(proven_wrong_diffs):
    """Soft, prompt-level trava: list proven-WRONG patches to AVOID. Never shows a correct fix (non-circular)."""
    if not proven_wrong_diffs:
        return ""
    blocks = []
    for i, d in enumerate(proven_wrong_diffs, 1):
        blocks.append(f"### Patch PROVADO ERRADO #{i} (já falhou nos testes — NÃO repita nem varie trivialmente):\n"
                      f"```diff\n{d.strip()}\n```")
    return ("\n\n---\n## TRAVAS — movimentos já provados ERRADOS nesta task\n"
            "Os patches abaixo JÁ foram tentados e FALHARAM na bateria de testes. Não os reaplique nem faça uma "
            "variação trivial deles; o erro está na ABORDAGEM, não num detalhe. Procure uma causa-raiz diferente.\n\n"
            + "\n\n".join(blocks) + "\n")


def run_driver(task_md_path, workdir, out_json, weights_file=None, max_steps=60):
    env = dict(os.environ)
    if weights_file:
        env["ATOMIC_WEIGHTS_FILE"] = weights_file
    else:
        env.pop("ATOMIC_WEIGHTS_FILE", None)
    cmd = [sys.executable, DRIVER, "--workdir", workdir, "--task", task_md_path,
           "--gate", "NONE", "--out", out_json, "--max-steps", str(max_steps)]
    subprocess.run(cmd, env=env, stdout=open(out_json + ".log", "w"), stderr=subprocess.STDOUT, timeout=3600)
    try:
        return (json.load(open(out_json)).get("final_diff") or "").strip()
    except Exception:
        return ""


def score(iid, diff, run_id):
    """Official SWE-bench harness verdict. Returns True/False/None."""
    pred = os.path.join(WORKROOT, f"pred_{run_id}.jsonl")
    os.makedirs(WORKROOT, exist_ok=True)
    with open(pred, "w") as f:
        f.write(json.dumps({"instance_id": iid, "model_name_or_path": f"refire-{run_id}",
                            "model_patch": diff or ""}) + "\n")
    log = os.path.join(WORKROOT, f"score_{run_id}.log")
    cmd = [sys.executable, "-m", "swebench.harness.run_evaluation",
           "--dataset_name", "princeton-nlp/SWE-bench_Verified", "--predictions_path", pred,
           "--run_id", run_id, "--max_workers", "1", "--cache_level", "instance"]
    try:
        subprocess.run(cmd, stdout=open(log, "w"), stderr=subprocess.STDOUT, timeout=1800)
    except Exception as e:
        return None
    txt = open(log, errors="ignore").read()
    m = re.search(r"Instances resolved:\s*(\d+)", txt)
    return (int(m.group(1)) >= 1) if m else None


def prep_workspace(iid, tag):
    src = os.path.join(SUITE, iid, "pristine")
    wd = os.path.join(WORKROOT, f"{iid}_{tag}")
    if not os.path.isdir(src):
        return None
    shutil.rmtree(wd, ignore_errors=True)
    os.makedirs(os.path.dirname(wd), exist_ok=True)
    shutil.copytree(src, wd)
    subprocess.run(["git", "-C", wd, "reset", "--hard", "-q", "HEAD"], check=False)
    subprocess.run(["git", "-C", wd, "clean", "-fdq"], check=False)
    return wd


def make_task_file(iid, gold, addendum, tag):
    base = os.path.join(LOOP, "tasks", f"SWE-{iid}", "PROBLEM.md")
    body = open(base).read() if os.path.exists(base) else gold[iid]["problem"]
    path = os.path.join(WORKROOT, f"task_{iid}_{tag}.md")
    os.makedirs(WORKROOT, exist_ok=True)
    open(path, "w").write(body + addendum)
    return path


def elimination_run(iid, gold, K):
    """Sequential re-fire with accumulating travas. Returns (resolved_bool, attempt_index_or_None, n_attempts)."""
    travas = []
    for i in range(K):
        wd = prep_workspace(iid, f"elim{i}")
        if wd is None:
            return None, None, i
        task_md = make_task_file(iid, gold, render_trava_addendum(travas), f"elim{i}")
        out = os.path.join(WORKROOT, f"{iid}_elim{i}.json")
        diff = run_driver(task_md, wd, out, weights_file=CORPUS)
        shutil.rmtree(wd, ignore_errors=True)
        rid = f"refire_{re.sub(chr(92)+'W','_',iid)}_elim{i}"
        res = score(iid, diff, rid)
        if res is True:
            return True, i, i + 1
        if diff and diff not in travas:
            travas.append(diff)
    return False, None, K


def baseline_run(iid, gold, K):
    """Best-of-K INDEPENDENT one-shots (same budget, NO elimination). Returns (resolved_bool, first_idx, K)."""
    for i in range(K):
        wd = prep_workspace(iid, f"base{i}")
        if wd is None:
            return None, None, i
        task_md = make_task_file(iid, gold, "", f"base{i}")
        out = os.path.join(WORKROOT, f"{iid}_base{i}.json")
        diff = run_driver(task_md, wd, out, weights_file=CORPUS)
        shutil.rmtree(wd, ignore_errors=True)
        rid = f"refire_{re.sub(chr(92)+'W','_',iid)}_base{i}"
        if score(iid, diff, rid) is True:
            return True, i, K
    return False, None, K


def selftest():
    """Validate the scoring plumbing WITHOUT the model: gold patch must resolve=1, empty must resolve=0."""
    iid = os.environ.get("SELFTEST_IID", "psf__requests-1921")
    g = gold_for([iid])
    if iid not in g:
        print(f"[selftest] {iid} not in dataset"); return
    print(f"[selftest] positive control: scoring GOLD patch for {iid} (must be resolved=1) ...")
    pos = score(iid, g[iid]["patch"], f"selftest_{re.sub(chr(92)+'W','_',iid)}_gold")
    print(f"[selftest] negative control: scoring EMPTY diff for {iid} (must be resolved=0) ...")
    neg = score(iid, "", f"selftest_{re.sub(chr(92)+'W','_',iid)}_empty")
    print(f"[selftest] RESULT: gold_resolved={pos}  empty_resolved={neg}  "
          f"PLUMBING_OK={pos is True and neg is False}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("task_ids", nargs="*")
    ap.add_argument("--k", type=int, default=6)
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        selftest(); return
    if not os.environ.get("DEEPSEEK_API_KEY"):
        print("BLOCKED: DEEPSEEK_API_KEY unset — the fixed student model (DeepSeek V4 Pro) cannot run, so a live "
              "'surpass baseline' number is impossible to produce. Provide a key (via env) and re-run. "
              "Run with --selftest to validate the scoring plumbing meanwhile.")
        sys.exit(2)
    task_ids = a.task_ids or RECOMMENDED_TASKS
    if not a.task_ids:
        print(f"[default] no task_ids given -> using RECOMMENDED_TASKS (network-free, heavy re-fire): {task_ids}")
    a.task_ids = task_ids
    gold = gold_for(a.task_ids)
    results = []
    for iid in a.task_ids:
        if iid not in gold:
            print(f"[skip] {iid} not in dataset"); continue
        print(f"=== {iid} : baseline best-of-{a.k} (no elimination) ===")
        b_res, b_idx, _ = baseline_run(iid, gold, a.k)
        print(f"  baseline_resolved={b_res} (first at {b_idx})")
        print(f"=== {iid} : sequential re-fire WITH elimination (K={a.k}) ===")
        e_res, e_idx, e_n = elimination_run(iid, gold, a.k)
        print(f"  elimination_resolved={e_res} (at attempt {e_idx}, {e_n} attempts)")
        results.append({"iid": iid, "baseline_resolved": b_res, "baseline_first": b_idx,
                        "elimination_resolved": e_res, "elimination_at": e_idx, "elimination_attempts": e_n})
    out = os.path.join(HERE, "refire_results.json")
    json.dump(results, open(out, "w"), indent=2)
    nb = sum(1 for r in results if r["baseline_resolved"])
    ne = sum(1 for r in results if r["elimination_resolved"])
    print(f"\n=== ELEVATION (weak form) BY NUMBER ===")
    print(f"  baseline best-of-{a.k} resolved:        {nb}/{len(results)}")
    print(f"  re-fire+elimination resolved:           {ne}/{len(results)}")
    print(f"  DELTA (elimination - baseline) = {ne - nb}  -> "
          f"{'SURPASSES' if ne > nb else 'NULL/parity' if ne == nb else 'NEGATIVE'}")
    print(f"  results: {out}")


if __name__ == "__main__":
    main()
