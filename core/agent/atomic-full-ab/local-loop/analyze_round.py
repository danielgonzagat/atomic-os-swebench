#!/usr/bin/env python3
"""
analyze_round.py — wall-hunting analyzer. Dumps EVERYTHING an atomic round did AND thought
(per the loop law: read winners and losers, full reasoning, enumerate invisible walls).

Usage:
  python3 analyze_round.py <result.json> [--full]      # one instance, full reasoning
  python3 analyze_round.py --suite <dir> [--baseline native_baseline_suite.json]  # compare suite vs native
"""
import json, sys, argparse, os, re

def short_id(task_or_path):
    m = re.search(r"SWE-([^/]+)/PROBLEM", task_or_path or "")
    if m: return m.group(1)
    return os.path.basename(task_or_path or "").replace("__atomic.json", "")

def total_calls(d):
    return sum(d.get("tool_calls", {}).values())

def dump_full(d):
    iid = short_id(d.get("task", ""))
    print(f"\n{'='*80}\nINSTANCE: {iid}")
    print(f"  total_calls={total_calls(d)} edits={d.get('edits_applied')} reads={d.get('reads')} "
          f"body_reads={d.get('body_context_reads')} invalid_prevented={d.get('invalid_states_prevented')} "
          f"diff_lines={d.get('diff_lines')} tokens={d.get('tokens')} wall={d.get('wall_s')}s steps={d.get('steps')}")
    print(f"  tool_calls={d.get('tool_calls')}")
    rt = {r["step"]: r for r in d.get("reasoning_trace", [])}
    # walk messages to interleave actions+results with reasoning
    msgs = d.get("messages", [])
    step = 0
    for m in msgs:
        role = m.get("role")
        if role == "assistant":
            step += 1
            r = rt.get(step, {})
            think = (r.get("reasoning") or "").strip()
            say = (m.get("content") or "").strip()
            print(f"\n--- step {step} ---")
            if think:
                print(f"  THINK: {think}")
            if say:
                print(f"  SAY: {say}")
            for c in (m.get("tool_calls") or []):
                fn = c["function"]["name"]; aa = c["function"]["arguments"]
                print(f"  CALL {fn}({aa[:300]})")
        elif role == "tool":
            res = (m.get("content") or "").strip()
            print(f"  RESULT: {res[:600]}")
        elif role == "user" and step > 0:
            print(f"  [STEER]: {(m.get('content') or '')[:200]}")

def suite_compare(dirpath, baseline_path):
    base = {}
    if os.path.exists(baseline_path):
        base = json.load(open(baseline_path)).get("instances", {})
    rows = []
    for fn in sorted(os.listdir(dirpath)):
        if not fn.endswith("__atomic.json"): continue
        d = json.load(open(os.path.join(dirpath, fn)))
        iid = short_id(d.get("task","")) or fn.replace("__atomic.json","")
        short = iid.split("__")[-1] if "__" in iid else iid
        # baseline keys are like "requests-1921"
        bkey = next((k for k in base if k in iid or iid.endswith(k)), None)
        nt = base.get(bkey, {}).get("tool_uses") if bkey else None
        rows.append((short, total_calls(d), nt, d.get("edits_applied"), d.get("diff_lines"), d.get("tokens"), d.get("wall_s")))
    print(f"\n{'instance':<16}{'atomic':>8}{'native':>8}{'winner':>10}{'edits':>7}{'diff':>6}{'tokens':>9}{'wall':>7}")
    ta=tn=0
    for short, a, n, e, df, tok, w in rows:
        win = "?" if n is None else ("ATOMIC" if a < n else ("native" if a > n else "tie"))
        ta += a; tn += (n or 0)
        print(f"{short:<16}{a:>8}{str(n):>8}{win:>10}{str(e):>7}{str(df):>6}{str(tok):>9}{str(w):>7}")
    print(f"{'TOTAL':<16}{ta:>8}{tn:>8}{('ATOMIC' if ta<tn else 'native' if ta>tn else 'tie'):>10}")

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("path", nargs="?")
    ap.add_argument("--suite")
    ap.add_argument("--baseline", default="native_baseline_suite.json")
    ap.add_argument("--full", action="store_true")
    a = ap.parse_args()
    if a.suite:
        suite_compare(a.suite, a.baseline)
    elif a.path:
        d = json.load(open(a.path))
        dump_full(d)
    else:
        ap.print_help()
