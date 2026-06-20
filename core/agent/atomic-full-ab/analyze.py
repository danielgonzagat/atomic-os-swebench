#!/usr/bin/env python3
"""analyze.py — honest attributable A/B analysis of two SWE-bench harness summaries.

Usage:
  python3 analyze.py --on <on_summary.json> --off <off_summary.json> [--label "..."]
  python3 analyze.py --selftest

Computes per-arm resolved rate, the attributable ON-OFF delta, McNemar's exact test on the paired
outcomes over the shared instance set, and an HONEST verdict that NEVER affirms revolution. Stdlib
only (McNemar via math.comb — no scipy).
"""
import argparse
import json
import math
import sys


def _ids(summary, key_variants):
    for k in key_variants:
        v = summary.get(k)
        if isinstance(v, list):
            return set(v)
    return set()


def arm_stats(s):
    submitted = s.get("submitted_instances")
    if submitted is None:
        submitted = len(_ids(s, ["submitted_ids"])) or s.get("total_instances", 0)
    resolved_ids = _ids(s, ["resolved_ids"])
    completed_ids = _ids(s, ["completed_ids"])
    resolved = s.get("resolved_instances", len(resolved_ids))
    return {
        "submitted": submitted or 0,
        "completed": s.get("completed_instances", len(completed_ids)),
        "resolved": resolved or 0,
        "empty_patch": s.get("empty_patch_instances", 0),
        "error": s.get("error_instances", 0),
        "resolved_ids": resolved_ids,
        "completed_ids": completed_ids,
        "resolved_rate": (resolved or 0) / submitted if submitted else 0.0,
    }


def mcnemar_exact_two_sided(b, c):
    """Exact binomial McNemar over discordant pairs (b, c). Returns p-value in [0,1]."""
    n = b + c
    if n == 0:
        return 1.0
    k = min(b, c)
    # two-sided exact: 2 * sum_{i=0..k} C(n,i) * 0.5^n, capped at 1
    tail = sum(math.comb(n, i) for i in range(0, k + 1)) * (0.5 ** n)
    return min(1.0, 2.0 * tail)


def verdict(delta, p, n_pairs):
    if delta <= 0:
        return "NO POSITIVE DELTA — atomic does not improve task-solving in this A/B."
    if p >= 0.05:
        return ("DIRECTIONAL ONLY — not statistically significant (underpowered, "
                f"n={n_pairs} discordant pairs, p={p:.4f}); NOT evidence of revolution.")
    return (f"SIGNIFICANT POSITIVE DELTA of +{delta*100:.1f}pp (McNemar p={p:.4f}, n={n_pairs}) — "
            "real, attributable improvement (still not 'revolution' unless large & replicated).")


def analyze(on, off, label=""):
    o, f = arm_stats(on), arm_stats(off)
    shared = o["completed_ids"] & f["completed_ids"]
    if not shared:
        shared = (o["resolved_ids"] | f["resolved_ids"])  # fallback: union of resolved
    on_only = sorted(o["resolved_ids"] - f["resolved_ids"])
    off_only = sorted(f["resolved_ids"] - o["resolved_ids"])
    # paired discordant counts over shared set
    b = len([i for i in off_only if i in shared]) or len(off_only)
    c = len([i for i in on_only if i in shared]) or len(on_only)
    p = mcnemar_exact_two_sided(b, c)
    delta = o["resolved_rate"] - f["resolved_rate"]
    v = verdict(delta, p, b + c)
    lines = []
    if label:
        lines.append(f"=== A/B: {label} ===")
    lines.append(f"ON  (full):  submitted={o['submitted']} completed={o['completed']} resolved={o['resolved']} "
                 f"empty={o['empty_patch']} error={o['error']} rate={o['resolved_rate']*100:.1f}%")
    lines.append(f"OFF (ctrl):  submitted={f['submitted']} completed={f['completed']} resolved={f['resolved']} "
                 f"empty={f['empty_patch']} error={f['error']} rate={f['resolved_rate']*100:.1f}%")
    lines.append(f"attributable delta (ON-OFF): {delta*100:+.1f}pp")
    lines.append(f"McNemar discordant: on_only(c)={c} off_only(b)={b}  exact two-sided p={p:.4f}")
    lines.append(f"solved ONLY by ON:  {on_only}")
    lines.append(f"solved ONLY by OFF: {off_only}")
    lines.append(f"VERDICT: {v}")
    return "\n".join(lines), {"delta": delta, "p": p, "verdict": v, "b": b, "c": c}


def _selftest():
    ok = True
    # branch 1: no positive delta
    on = {"submitted_instances": 10, "resolved_instances": 1, "resolved_ids": ["a"], "completed_ids": ["a", "b"]}
    off = {"submitted_instances": 10, "resolved_instances": 2, "resolved_ids": ["a", "b"], "completed_ids": ["a", "b"]}
    _, r = analyze(on, off)
    ok &= "NO POSITIVE DELTA" in r["verdict"]; print("  [%s] no_positive_delta" % ("OK" if "NO POSITIVE DELTA" in r["verdict"] else "X"))
    # branch 2: directional only (delta>0, p>=.05): b=0,c=1 -> p=1.0
    on = {"submitted_instances": 10, "resolved_instances": 2, "resolved_ids": ["a", "b"], "completed_ids": ["a", "b", "x"]}
    off = {"submitted_instances": 10, "resolved_instances": 1, "resolved_ids": ["a"], "completed_ids": ["a", "b", "x"]}
    _, r = analyze(on, off)
    ok &= "DIRECTIONAL ONLY" in r["verdict"]; print("  [%s] directional_only" % ("OK" if "DIRECTIONAL ONLY" in r["verdict"] else "X"))
    # branch 3: significant (delta>0, p<.05): b=0,c=12 -> p~=0.0005
    onids = ["r%d" % i for i in range(12)] + ["base"]
    on = {"submitted_instances": 50, "resolved_instances": 13, "resolved_ids": onids, "completed_ids": onids}
    off = {"submitted_instances": 50, "resolved_instances": 1, "resolved_ids": ["base"], "completed_ids": onids}
    _, r = analyze(on, off)
    ok &= "SIGNIFICANT POSITIVE DELTA" in r["verdict"]; print("  [%s] significant_positive_delta" % ("OK" if "SIGNIFICANT POSITIVE DELTA" in r["verdict"] else "X"))
    print("self-test:", "PASS" if ok else "FAIL")
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--on")
    ap.add_argument("--off")
    ap.add_argument("--label", default="")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        sys.exit(0 if _selftest() else 1)
    if not (a.on and a.off):
        ap.error("need --on and --off (or --selftest)")
    on = json.load(open(a.on))
    off = json.load(open(a.off))
    text, _ = analyze(on, off, a.label)
    print(text)


if __name__ == "__main__":
    main()
