#!/usr/bin/env python3
"""ATTACK: metric_harshness.

The harness recall_fp0 sets thr = max(fp_sims)+eps -> ONE worst-case held-out CORRECT move
sets a hard wall. If that wall sits near 1.0 (near-duplicate correct/failed moves), recall_fp0
is artificially crushed. This attack recomputes FAIRER, still-sound metrics from the SAME
leave-one-bug-out tp/fp similarity distributions:

  - AUC        : prob that a held-out FAILED move scores higher than a held-out CORRECT move
                 against the cross-bug FAILED bank (rank separation; threshold-free).
  - recall@FP1 : recall when we allow the global threshold to sit at the 99th pct of fp_sims
                 (i.e. tolerate 1% of correct moves being blocked) -- still mostly sound.
  - recall@FP5 : same at 95th pct (tolerate 5%).
  - recall_fp0 : the harness's own number, recomputed here for cross-check.

We DO NOT touch the encoders (reuse sweep.py's). We re-extract tp_sims/fp_sims with the SAME
LOBO protocol the harness uses, then derive the fairer metrics. Every number is computed; the
question = does ANY structural signature beat lexical AND clear a useful bar under the fair metric.
"""
import re, os, sys
import numpy as np
from collections import defaultdict, Counter
import trava_harness as H
import sweep as SW   # reuse the exact signatures already tried

A, C = H.load()
D = H.D

def lobo_sims(encode_fn, attempts, ctx):
    """Replicate harness LOBO EXACTLY, but return the raw tp_sims / fp_sims distributions."""
    def enc(a):
        r = encode_fn(a, ctx)
        if r and isinstance(r, list) and len(r) == D and isinstance(r[0], (int, float)):
            return r
        return H.encode_tokens(r if r is not None else [])
    vecs = [enc(a) for a in attempts]
    M = np.array(vecs, dtype=np.float64)
    S = np.nan_to_num((M @ M.T) / D)
    iid = np.array([a['iid'] for a in attempts])
    isfail = np.array([a['gp'] is not True for a in attempts])
    iscorr = ~isfail
    N = len(attempts)
    by_bug = defaultdict(list)
    for k, a in enumerate(attempts):
        if a['gp'] is not True:
            by_bug[a['iid']].append(k)
    bugs = [b for b, v in by_bug.items() if len(v) >= 2]
    tp_sims, fp_sims = [], []
    for held in bugs:
        bank = np.array([k for k in range(N) if isfail[k] and iid[k] != held])
        if bank.size == 0:
            continue
        held_fail = [k for k in range(N) if isfail[k] and iid[k] == held]
        held_corr = [k for k in range(N) if iscorr[k] and iid[k] == held]
        for t in held_fail:
            tp_sims.append(float(S[t, bank].max()))
        for c in held_corr:
            fp_sims.append(float(S[c, bank].max()))
    return np.array(tp_sims), np.array(fp_sims)

def auc(tp, fp):
    """P(random tp > random fp) with ties at 0.5. Threshold-free rank separation."""
    if len(tp) == 0 or len(fp) == 0:
        return float('nan')
    # Mann-Whitney U / (n_tp * n_fp)
    allv = np.concatenate([tp, fp])
    order = allv.argsort(kind='mergesort')
    ranks = np.empty(len(allv), dtype=np.float64)
    # average ranks for ties
    sv = allv[order]
    i = 0
    r = np.empty(len(allv))
    while i < len(sv):
        j = i
        while j + 1 < len(sv) and sv[j+1] == sv[i]:
            j += 1
        avg = (i + j) / 2.0 + 1.0  # 1-based avg rank
        r[i:j+1] = avg
        i = j + 1
    ranks[order] = r
    n_tp = len(tp)
    rank_tp = ranks[:n_tp]
    U = rank_tp.sum() - n_tp * (n_tp + 1) / 2.0
    return U / (n_tp * len(fp))

def recall_at_fp(tp, fp, fp_rate):
    """Threshold = the (1-fp_rate) quantile of fp_sims => exactly fp_rate of correct moves blocked.
    Recall = fraction of failed moves at/above that threshold. fp_rate=0 -> harness behavior (max)."""
    if len(tp) == 0:
        return float('nan')
    if len(fp) == 0:
        return 1.0  # nothing to be sound against
    if fp_rate <= 0:
        thr = fp.max() + 1e-9
    else:
        # block fp_rate of correct moves: threshold = quantile so that fraction >= thr is fp_rate
        thr = np.quantile(fp, 1.0 - fp_rate)
    return float((tp >= thr).mean())

SIGS = SW.SIGS  # all 11 already-tried signatures + lexical baseline

print(f"{'signature':34s} {'legal':6s} {'AUC':>7s} {'r@FP0':>7s} {'r@FP1':>7s} {'r@FP5':>7s} "
      f"{'fpmax':>7s} {'#tp':>5s} {'#fp':>5s}")
print("-" * 100)

rows = []
lex = {}
for name, fn, legal in SIGS:
    tp, fp = lobo_sims(fn, [dict(x) for x in A], C)
    a = auc(tp, fp)
    r0 = recall_at_fp(tp, fp, 0.0)
    r1 = recall_at_fp(tp, fp, 0.01)
    r5 = recall_at_fp(tp, fp, 0.05)
    fpmax = float(fp.max()) if len(fp) else float('nan')
    row = dict(name=name, legal=legal, auc=a, r0=r0, r1=r1, r5=r5, fpmax=fpmax,
               ntp=len(tp), nfp=len(fp))
    rows.append(row)
    if name.startswith('LEXICAL'):
        lex = row
    short = name[:34]
    print(f"{short:34s} {str(legal):6s} {a:7.3f} {r0:7.3f} {r1:7.3f} {r5:7.3f} "
          f"{fpmax:7.3f} {len(tp):5d} {len(fp):5d}")

print("-" * 100)
print(f"LEXICAL baseline: AUC={lex['auc']:.3f}  r@FP0={lex['r0']:.3f}  r@FP1={lex['r1']:.3f}  r@FP5={lex['r5']:.3f}")
print()
# Does ANY structural sig beat lexical AND clear a useful bar under the FAIR metric?
# Fair bar candidates: AUC > 0.5 (better than chance rank-sep) AND > lexical AUC;
#                      r@FP5 > 0.25 AND > lexical r@FP5.
print("=== FAIR-METRIC VERDICT (model-free structural sigs, excluding lexical & posthoc) ===")
useful = []
for r in rows:
    if r['name'].startswith('LEXICAL'):
        continue
    posthoc = (r['legal'] is False)
    beats_auc = (r['auc'] > 0.5) and (r['auc'] > lex['auc'])
    beats_r5  = (np.isfinite(r['r5']) and r['r5'] > 0.25 and r['r5'] > lex['r5'])
    tag = []
    if beats_auc: tag.append('AUC>lex&>0.5')
    if beats_r5:  tag.append('r@FP5>lex&>0.25')
    verdict = ('USEFUL[' + ','.join(tag) + ']') if (beats_auc or beats_r5) else 'no'
    if posthoc:
        verdict += ' (POSTHOC-ceiling, not a real trava)'
    if (beats_auc or beats_r5) and not posthoc:
        useful.append(r['name'])
    print(f"  {r['name']:34s} AUC={r['auc']:.3f} r@FP5={r['r5']:.3f}  -> {verdict}")
print()
print(f"APPLY-TIME-LEGAL structural sigs that are USEFUL under the FAIR metric: {useful if useful else 'NONE'}")
