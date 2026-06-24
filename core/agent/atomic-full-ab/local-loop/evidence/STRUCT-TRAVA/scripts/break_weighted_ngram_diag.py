#!/usr/bin/env python3
"""Forensic: is the weighted_ngram null a fixable weighting artifact, or a real structural wall?
Confirm the FP0 collision is genuine (a correct move structurally ~ a cross-bug failure), and test the
BEST CASE for weighting: even an ORACLE idf that maximally down-weights tokens shared with correct moves."""
import re, os, math, hashlib
from collections import Counter, defaultdict
import numpy as np
import trava_harness as H

A, C = H.load()

def diff_ngram_tokens(diff, n_lo=1, n_hi=3):
    add, rem = H.diff_added_removed(diff)
    toks = Counter()
    for role, lines in (('A', add), ('D', rem)):
        for l in lines:
            ab = H.abstract_line(l); L = len(ab)
            for n in range(n_lo, n_hi+1):
                for i in range(L-n+1):
                    toks[role+':G%d:'%n + '>'.join(ab[i:i+n])] += 1
    return toks

PERDOC = [diff_ngram_tokens(a['fd']) for a in A]

# locate the poisoning collision: pylint-7080 correct move vs its nearest cross-bug failure
iidx = {i: a['iid'] for i, a in enumerate(A)}
isfail = [a['gp'] is not True for a in A]
corr_7080 = [i for i, a in enumerate(A) if a['iid'] == 'pylint-dev__pylint-7080' and a['gp'] is True]
print("correct moves for pylint-7080:", corr_7080)

# build raw idf cosine vecs (jaccard-ish on token sets, weighting-agnostic upper bound)
def jaccard(i, j):
    si, sj = set(PERDOC[i]), set(PERDOC[j])
    if not si or not sj: return 0.0
    return len(si & sj) / len(si | sj)

for ci in corr_7080:
    best = sorted(((jaccard(ci, j), j) for j in range(len(A))
                   if isfail[j] and iidx[j] != 'pylint-dev__pylint-7080'),
                  reverse=True)[:3]
    print(f"\ncorrect move idx={ci} (pylint-7080) nearest cross-bug FAILURES by Jaccard of abstracted n-grams:")
    for s, j in best:
        shared = set(PERDOC[ci]) & set(PERDOC[j])
        print(f"   jaccard={s:.3f} failbug={iidx[j]}  |shared_tokens|={len(shared)}")
        print(f"      sample shared: {sorted(list(shared))[:8]}")

# ORACLE-weighting test (NOT a legal signature; an UPPER BOUND on what weighting could do):
# weight each token by how MUCH it is failure-specific = df_in_failures / df_in_correct (purity).
# If even oracle purity-weighting can't separate, weighting is a dead lever -> rigorous null.
nfail = sum(isfail); ncorr = len(A) - nfail
df_f = Counter(); df_c = Counter()
for i, tks in enumerate(PERDOC):
    for t in set(tks):
        if isfail[i]: df_f[t] += 1
        else: df_c[t] += 1
# purity weight: tokens appearing ONLY in failures get high weight; tokens in correct moves get ~0
oracle_w = {}
for t in set(df_f) | set(df_c):
    pf = df_f.get(t, 0) / max(nfail, 1)
    pc = df_c.get(t, 0) / max(ncorr, 1)
    oracle_w[t] = max(0.0, pf - pc)  # positive only if more common in failures

def oracle_vec(i, dim=16384):
    v = np.zeros(dim)
    for t, c in PERDOC[i].items():
        w = oracle_w.get(t, 0.0) * (1 + math.log(c))
        if w <= 0: continue
        h = hashlib.sha256(t.encode()).digest()
        for j in range(2):
            idx = int.from_bytes(h[j*4:j*4+4], 'big') % dim
            sgn = 1.0 if (h[16+j] & 1) else -1.0
            v[idx] += w * sgn
    n = np.linalg.norm(v)
    return v / n if n > 0 else v

M = np.array([oracle_vec(i) for i in range(len(A))])
S = np.nan_to_num(M @ M.T)
iid = np.array([a['iid'] for a in A]); isf = np.array(isfail)
N = len(A)
by_bug = defaultdict(list)
for k, a in enumerate(A):
    if a['gp'] is not True: by_bug[a['iid']].append(k)
bugs = [b for b, v in by_bug.items() if len(v) >= 2]
tp, fp = [], []
for held in bugs:
    bank = np.array([k for k in range(N) if isf[k] and iid[k] != held])
    for t in [k for k in range(N) if isf[k] and iid[k] == held]: tp.append(float(S[t, bank].max()))
    for c in [k for k in range(N) if (not isf[k]) and iid[k] == held]: fp.append(float(S[c, bank].max()))
thr = max(fp) + 1e-9 if fp else None
rec = sum(1 for s in tp if s >= thr)/len(tp) if (thr and tp) else None
print(f"\n[ORACLE purity-weighting UPPER BOUND] recall_fp0={rec}  thr={thr:.3f}  (fp wall set by max fp_sim)")
print(f"    n_correct collisions vec'd (oracle, many correct moves still have failure-only-token mass): "
      f"{sum(1 for s in fp if s>0)}")
print(f"    top fp_sims: {sorted(fp, reverse=True)[:5]}")
print("\nINTERPRETATION: oracle purity-weighting is the THEORETICAL CEILING of any rarity/idf weighting.")
print("If it can't separate, the weighted_ngram angle is a structural null, not a tuning miss.")
