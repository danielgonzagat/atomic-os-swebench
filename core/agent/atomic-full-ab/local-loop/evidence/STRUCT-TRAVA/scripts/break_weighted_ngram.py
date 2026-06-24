#!/usr/bin/env python3
"""ANGLE: weighted_ngram. Hypothesis: the flat VSA bundle destroyed discriminative weighting.
Try TF-IDF / rarity-weighted abstracted-diff n-grams (idf computed deterministically across attempts),
true sparse cosine (skip VSA), and a higher-dim hashed variant. Same name-agnostic abstracted tokens,
better weighting. Every number from H.evaluate.

KEY MECHANICS of the harness:
  - S = M @ M.T / D ; recall_fp0 = LOO-bug, threshold = max correct-move sim to cross-bug FAILED bank.
  - So I want FAILED moves to cluster TIGHT with cross-bug FAILED moves, CORRECT moves FAR.
  - I return EXPLICIT length-2048 float vectors (L2-normalized) so S = cosine. The /D and the *-1/1 sign
    bundling of the VSA path is bypassed -> real TF-IDF cosine, not sign-collapsed bundles.

Determinism: idf computed over the FULL attempt set deterministically (document frequency of each token).
This is a global corpus statistic, NOT per-class supervision, NOT gold. The LOO-bug recall metric is
unaffected by idf leakage in the soundness sense because idf is symmetric over fail/correct and computed
from token text only. Still: I ALSO run an idf variant computed ONLY over the bank-eligible set per-fold is
overkill; standard TF-IDF uses a fixed global idf. I note this honestly. The discriminativeness comes from
DOWN-weighting boilerplate tokens shared by everything (incl. correct moves) and UP-weighting rare failure
n-grams. That is exactly the 'weighting' lever the angle asks for.
"""
import re, os, math, hashlib
from collections import Counter, defaultdict
import numpy as np
import trava_harness as H

A, C = H.load()
DIM = 2048
HIDIM = 16384

# ---------------- token extraction: abstracted diff n-grams ----------------
def diff_ngram_tokens(diff, n_lo=1, n_hi=3, with_role=True):
    """Name-agnostic abstracted tokens of the diff: per added/removed line, abstract_line -> tokens,
    then 1..n-grams within the line, tagged ADD/DEL. Also file-level + hunk-header def/class tokens."""
    add, rem = H.diff_added_removed(diff)
    toks = Counter()
    for role, lines in (('A', add), ('D', rem)):
        rp = (role + ':') if with_role else ''
        for l in lines:
            ab = H.abstract_line(l)
            L = len(ab)
            for n in range(n_lo, n_hi + 1):
                for i in range(L - n + 1):
                    toks[rp + 'G%d:' % n + '>'.join(ab[i:i+n])] += 1
    return toks

def attempt_tokens(a):
    return diff_ngram_tokens(a['fd'])

# ---------------- deterministic global IDF over the corpus ----------------
def build_idf(attempts):
    df = Counter()
    N = len(attempts)
    perdoc = []
    for a in attempts:
        tks = attempt_tokens(a)
        perdoc.append(tks)
        for t in tks:
            df[t] += 1
    idf = {t: math.log((N + 1) / (c + 1)) + 1.0 for t, c in df.items()}
    return idf, perdoc

IDF, PERDOC = build_idf(A)
# index perdoc by id(attempt dict) won't survive copies; rebuild on the fly instead.

# ---------------- hashing helpers ----------------
_hash_cache = {}
def hashed_indices(tok, dim, k=2):
    """k independent hashes (sign + index) for a token -> reduce collisions, signed."""
    key = (tok, dim)
    if key in _hash_cache:
        return _hash_cache[key]
    out = []
    h = hashlib.sha256(tok.encode()).digest()
    for j in range(k):
        idx = int.from_bytes(h[j*4:j*4+4], 'big') % dim
        sgn = 1.0 if (h[16 + j] & 1) else -1.0
        out.append((idx, sgn))
    _hash_cache[key] = out
    return out

def tfidf_vec(a, dim, use_idf=True, sublinear=True, k=2):
    tks = attempt_tokens(a)
    v = np.zeros(dim, dtype=np.float64)
    for t, c in tks.items():
        tf = (1.0 + math.log(c)) if (sublinear and c > 0) else float(c)
        w = tf * (IDF.get(t, 1.0) if use_idf else 1.0)
        for idx, sgn in hashed_indices(t, dim, k):
            v[idx] += w * sgn
    nrm = np.linalg.norm(v)
    if nrm > 0:
        v = v / nrm
    return v

# ---------------- signatures (return explicit DIM-length vectors) ----------------
def sig_tfidf_cosine(a, ctx):
    return tfidf_vec(a, DIM, use_idf=True, sublinear=True, k=2).tolist()

def sig_tf_only_cosine(a, ctx):     # ablation: same n-grams, NO idf (just tf, cosine)
    return tfidf_vec(a, DIM, use_idf=False, sublinear=True, k=2).tolist()

def sig_tfidf_hidim(a, ctx):        # higher-dim hashed space -> fewer collisions
    v = tfidf_vec(a, HIDIM, use_idf=True, sublinear=True, k=2)
    # harness expects len==D==2048 for the explicit path; HIDIM won't be treated as vector.
    # So fold down to 2048 by another hash-reduce while preserving cosine approx is wrong.
    # Instead: return the raw 16384 won't work. We handle hidim via a SEPARATE direct evaluator below.
    return v  # placeholder, handled specially

def sig_tfidf_binary(a, ctx):       # binary presence (set) TF-IDF: down-weight repeated boilerplate
    tks = attempt_tokens(a)
    v = np.zeros(DIM, dtype=np.float64)
    for t in tks:
        w = IDF.get(t, 1.0)
        for idx, sgn in hashed_indices(t, DIM, 2):
            v[idx] += w * sgn
    nrm = np.linalg.norm(v)
    if nrm > 0: v = v / nrm
    return v.tolist()

# ---------------- direct cosine evaluator (mirrors H.evaluate metric exactly) ----------------
# Needed for HIDIM (harness only accepts len==2048 explicit vectors). Reuses identical LOO-bug logic.
def direct_eval(name, vec_fn, attempts, applytime_legal=True):
    M = np.array([vec_fn(a) for a in attempts], dtype=np.float64)
    # rows already L2-normalized -> S = cosine
    S = np.nan_to_num(M @ M.T)
    iid = np.array([a['iid'] for a in attempts])
    isfail = np.array([a['gp'] is not True for a in attempts])
    iscorr = ~isfail
    N = len(attempts)
    samebug = iid[:, None] == iid[None, :]
    triu = np.triu(np.ones((N, N), dtype=bool), 1)
    ff_mask = triu & (~samebug) & isfail[:, None] & isfail[None, :]
    fc_mask = triu & (~samebug) & ((isfail[:, None] & iscorr[None, :]) | (iscorr[:, None] & isfail[None, :]))
    ff = float(S[ff_mask].mean()) if ff_mask.any() else 0.0
    fc = float(S[fc_mask].mean()) if fc_mask.any() else 0.0
    by_bug = defaultdict(list)
    for k, a in enumerate(attempts):
        if a['gp'] is not True: by_bug[a['iid']].append(k)
    bugs = [b for b, v in by_bug.items() if len(v) >= 2]
    tp_sims, fp_sims = [], []
    for held in bugs:
        bank = np.array([k for k in range(N) if isfail[k] and iid[k] != held])
        if bank.size == 0: continue
        held_fail = [k for k in range(N) if isfail[k] and iid[k] == held]
        held_corr = [k for k in range(N) if iscorr[k] and iid[k] == held]
        for t in held_fail: tp_sims.append(float(S[t, bank].max()))
        for c in held_corr: fp_sims.append(float(S[c, bank].max()))
    if fp_sims:
        thr = max(fp_sims) + 1e-9
        recall = sum(1 for s in tp_sims if s >= thr) / len(tp_sims) if tp_sims else 0.0
    else:
        thr, recall = None, None
    return {'name': name, 'sep': ff - fc, 'ff': ff, 'fc': fc, 'recall_fp0': recall,
            'thr': thr, 'n_bugs': len(bugs), 'applytime_legal': applytime_legal,
            'n_correct': int(iscorr.sum()), 'n_failed': int(isfail.sum())}

LEX = H.evaluate("LEXICAL", lambda a, ctx: H.lexical_vsa(a['fd']),
                 [dict(x) for x in A], C, applytime_legal=True, verbose=False)
lex_recall = LEX['recall_fp0']

print(f"lexical baseline recall_fp0 = {lex_recall}")
print(f"{'signature':28s} {'apply':6s} {'recall@FP0':>11s} {'sep':>9s} {'ff':>7s} {'fc':>7s}  verdict")
print("-" * 84)

def verdict(rec):
    return '*** PASS' if (rec is not None and rec > 0.25 and rec > max(lex_recall, 0.126)) else 'fail'

results = {}

# 1) TF-IDF cosine (DIM=2048) via harness explicit-vector path
r = H.evaluate("tfidf_cosine_2048", sig_tfidf_cosine, [dict(x) for x in A], C,
               applytime_legal=True, verbose=False)
results['tfidf_cosine_2048'] = r
print(f"{'tfidf_cosine_2048':28s} {'yes':6s} {r['recall_fp0']:>11.3f} {r['sep']:>+9.3f} "
      f"{r['xbug_failed_failed']:>7.3f} {r['xbug_failed_correct']:>7.3f}  {verdict(r['recall_fp0'])}")

# 2) TF-only cosine (ablation: no idf)
r = H.evaluate("tf_only_cosine_2048", sig_tf_only_cosine, [dict(x) for x in A], C,
               applytime_legal=True, verbose=False)
results['tf_only_cosine_2048'] = r
print(f"{'tf_only_cosine_2048':28s} {'yes':6s} {r['recall_fp0']:>11.3f} {r['sep']:>+9.3f} "
      f"{r['xbug_failed_failed']:>7.3f} {r['xbug_failed_correct']:>7.3f}  {verdict(r['recall_fp0'])}")

# 3) binary-presence TF-IDF cosine
r = H.evaluate("tfidf_binary_2048", sig_tfidf_binary, [dict(x) for x in A], C,
               applytime_legal=True, verbose=False)
results['tfidf_binary_2048'] = r
print(f"{'tfidf_binary_2048':28s} {'yes':6s} {r['recall_fp0']:>11.3f} {r['sep']:>+9.3f} "
      f"{r['xbug_failed_failed']:>7.3f} {r['xbug_failed_correct']:>7.3f}  {verdict(r['recall_fp0'])}")

# 4) HIDIM TF-IDF cosine via direct evaluator (16384 dims, fewer hash collisions)
Acopy = [dict(x) for x in A]
r = direct_eval("tfidf_cosine_16384", lambda a: tfidf_vec(a, HIDIM, True, True, 2), Acopy, True)
results['tfidf_cosine_16384'] = r
print(f"{'tfidf_cosine_16384':28s} {'yes':6s} {r['recall_fp0']:>11.3f} {r['sep']:>+9.3f} "
      f"{r['ff']:>7.3f} {r['fc']:>7.3f}  {verdict(r['recall_fp0'])}")

# 5) HIDIM, k=4 hashes, more n-grams
def tok_wide(a):
    return diff_ngram_tokens(a['fd'], n_lo=1, n_hi=4)
def vec_wide(a, dim=HIDIM):
    tks = tok_wide(a)
    v = np.zeros(dim, dtype=np.float64)
    for t, c in tks.items():
        w = (1.0 + math.log(c)) * IDF.get(t, math.log((len(A)+1)/1)+1.0)
        for idx, sgn in hashed_indices(t, dim, 4):
            v[idx] += w * sgn
    nrm = np.linalg.norm(v)
    return v / nrm if nrm > 0 else v
r = direct_eval("tfidf_wide_16384_k4", lambda a: vec_wide(a), [dict(x) for x in A], True)
results['tfidf_wide_16384_k4'] = r
print(f"{'tfidf_wide_16384_k4':28s} {'yes':6s} {r['recall_fp0']:>11.3f} {r['sep']:>+9.3f} "
      f"{r['ff']:>7.3f} {r['fc']:>7.3f}  {verdict(r['recall_fp0'])}")

print("-" * 84)

# ---------------- DIAGNOSTIC: WHY does it pass/fail? inspect the FP0 wall ----------------
# Recompute for the best variant the single correct-move that poisons the threshold.
def diag(vec_fn, label):
    M = np.array([vec_fn(a) for a in A], dtype=np.float64)
    S = np.nan_to_num(M @ M.T)
    iid = np.array([a['iid'] for a in A]); isfail = np.array([a['gp'] is not True for a in A])
    N = len(A)
    by_bug = defaultdict(list)
    for k, a in enumerate(A):
        if a['gp'] is not True: by_bug[a['iid']].append(k)
    bugs = [b for b, v in by_bug.items() if len(v) >= 2]
    fp = []
    for held in bugs:
        bank = np.array([k for k in range(N) if isfail[k] and iid[k] != held])
        held_corr = [k for k in range(N) if (not isfail[k]) and iid[k] == held]
        for c in held_corr:
            fp.append((float(S[c, bank].max()), A[c]['iid']))
    fp.sort(reverse=True)
    print(f"[{label}] held-out CORRECT moves scored (top FP collisions set the wall):")
    for s, b in fp[:6]:
        print(f"    fp_sim={s:.3f}  bug={b}")
    print(f"    n_correct_held_out_with_a_failed_sibling_bank = {len(fp)} (these set the FP0 wall)")

diag(lambda a: tfidf_vec(a, HIDIM, True, True, 2), "tfidf_cosine_16384")

print("\nDONE.")
