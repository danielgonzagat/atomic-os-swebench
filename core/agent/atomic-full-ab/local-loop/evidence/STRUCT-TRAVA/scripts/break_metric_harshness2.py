#!/usr/bin/env python3
"""ATTACK metric_harshness — STAGE 2: are the high r@FP5 'USEFUL' hits real, or quantile/tie/degeneracy artifacts?

Stage-1 flagged edit_op_taxonomy/change_polarity/ast_nodetype_hist/tb_relation/indent_shape as 'USEFUL'
under recall@FP5. But fpmax=1.000 + only 23 fp samples => the threshold can be set by saturated ties.
This stage stress-tests each apparent hit:

  (1) TIE DIAGNOSIS: how many distinct vectors? how many tp_sims / fp_sims are EXACTLY 1.0 (collisions)?
      A signature that collapses many attempts to ONE vector => everything self-matches at 1.0 =>
      r@FP5 is a coin flip on which side of the saturated tie the quantile lands. (This is the SAME
      NO_TRACEBACK degeneracy the harness already called out for tb_relation's +0.511 sep.)

  (2) ROBUST recall@FP5 with STRICT inequality at a tie-broken threshold: a SOUND trava must not block
      correct moves; if tp and fp pile up at the SAME value (1.0), you cannot separate them at any FP
      budget without blocking correct. Recompute recall using thr = quantile but require tp STRICTLY
      above the highest fp that is *not* blocked => if fp has mass at 1.0, real recall collapses.

  (3) BOOTSTRAP 95% CI on AUC (resample bugs) so we know whether AUC>0.5 is signal or noise at n=23 fp.

  (4) The honest fair metric: AUC is threshold-free and tie-aware (already 0.5 for ties). Report it as
      the PRIMARY fair number. recall@FP5 is shown to be NON-ROBUST (quantile on a saturated tie).
"""
import numpy as np
from collections import defaultdict
import trava_harness as H
import sweep as SW

A, C = H.load()
D = H.D

def encode_all(encode_fn, attempts, ctx):
    def enc(a):
        r = encode_fn(a, ctx)
        if r and isinstance(r, list) and len(r) == D and isinstance(r[0], (int, float)):
            return r
        return H.encode_tokens(r if r is not None else [])
    return np.array([enc(a) for a in attempts], dtype=np.float64)

def lobo_sims_with_bugid(encode_fn, attempts, ctx):
    M = encode_all(encode_fn, attempts, ctx)
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
    tp_sims, tp_bug, fp_sims, fp_bug = [], [], [], []
    for held in bugs:
        bank = np.array([k for k in range(N) if isfail[k] and iid[k] != held])
        if bank.size == 0:
            continue
        held_fail = [k for k in range(N) if isfail[k] and iid[k] == held]
        held_corr = [k for k in range(N) if iscorr[k] and iid[k] == held]
        for t in held_fail:
            tp_sims.append(float(S[t, bank].max())); tp_bug.append(held)
        for c in held_corr:
            fp_sims.append(float(S[c, bank].max())); fp_bug.append(held)
    # distinct-vector diagnosis
    rows_as_tuple = [tuple(np.sign(M[k]).astype(int)) for k in range(N)]
    ndistinct = len(set(rows_as_tuple))
    return (np.array(tp_sims), np.array(tp_bug, dtype=object),
            np.array(fp_sims), np.array(fp_bug, dtype=object), N, ndistinct)

def auc(tp, fp):
    if len(tp) == 0 or len(fp) == 0: return float('nan')
    allv = np.concatenate([tp, fp]); order = allv.argsort(kind='mergesort'); sv = allv[order]
    r = np.empty(len(allv)); i = 0
    while i < len(sv):
        j = i
        while j + 1 < len(sv) and sv[j+1] == sv[i]: j += 1
        r[i:j+1] = (i + j)/2.0 + 1.0; i = j + 1
    ranks = np.empty(len(allv)); ranks[order] = r
    n_tp = len(tp); U = ranks[:n_tp].sum() - n_tp*(n_tp+1)/2.0
    return U/(n_tp*len(fp))

def robust_recall_at_fp(tp, fp, fp_rate):
    """SOUND-aware: we block everything >= thr. We are allowed to block fp_rate of correct moves.
    Pick the LOWEST thr such that fraction of fp blocked <= fp_rate. Then recall = frac tp blocked.
    Crucially, if fp has mass at value v, any thr<=v blocks ALL of it; so the achievable thresholds
    are just the fp values themselves (+inf). This is the honest staircase, tie-correct."""
    if len(tp) == 0: return float('nan')
    if len(fp) == 0: return 1.0
    cands = np.unique(np.concatenate([fp, [fp.max() + 1e-9]]))
    best = 0.0
    for thr in cands:
        fp_blocked = (fp >= thr).mean()
        if fp_blocked <= fp_rate + 1e-12:
            best = max(best, (tp >= thr).mean())
    return float(best)

print(f"{'signature':30s} {'Nvec':>5s} {'#distinct':>9s} {'tp@1.0':>7s} {'fp@1.0':>7s} "
      f"{'AUC':>6s} {'AUC_CI95':>14s} {'rr@FP5':>7s}")
print("-" * 100)

rng = np.random.default_rng(0)
for name, fn, legal in SW.SIGS:
    tp, tpb, fp, fpb, N, nd = lobo_sims_with_bugid(fn, [dict(x) for x in A], C)
    tp1 = float((tp >= 0.9999).mean()) if len(tp) else float('nan')
    fp1 = float((fp >= 0.9999).mean()) if len(fp) else float('nan')
    a = auc(tp, fp)
    # bootstrap CI by resampling BUGS (cluster bootstrap)
    bugs = sorted(set(list(tpb) + list(fpb)))
    aucs = []
    tp_by = defaultdict(list); fp_by = defaultdict(list)
    for v, b in zip(tp, tpb): tp_by[b].append(v)
    for v, b in zip(fp, fpb): fp_by[b].append(v)
    for _ in range(400):
        samp = rng.choice(len(bugs), len(bugs), replace=True)
        st, sf = [], []
        for idx in samp:
            b = bugs[idx]; st += tp_by[b]; sf += fp_by[b]
        if st and sf:
            aucs.append(auc(np.array(st), np.array(sf)))
    lo, hi = (np.percentile(aucs, 2.5), np.percentile(aucs, 97.5)) if aucs else (float('nan'), float('nan'))
    rr5 = robust_recall_at_fp(tp, fp, 0.05)
    print(f"{name[:30]:30s} {N:5d} {nd:9d} {tp1:7.3f} {fp1:7.3f} {a:6.3f} "
          f"[{lo:5.3f},{hi:5.3f}] {rr5:7.3f}")

print("-" * 100)
print("READ: #distinct << Nvec  => vector collapse (degeneracy). fp@1.0 > 0 => saturated ties =>")
print("naive quantile recall@FP5 is a coin flip. rr@FP5 = tie-correct robust recall (honest staircase).")
print("AUC_CI95 straddling 0.5 => no real cross-bug failed-vs-correct rank separation.")
