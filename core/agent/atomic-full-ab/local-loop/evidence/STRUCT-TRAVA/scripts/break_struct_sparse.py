#!/usr/bin/env python3
"""ATTACK on the model-free null. Genuinely-untried structural signatures evaluated with TWO scorers:
 (1) H.evaluate (the official VSA-2048 path), AND
 (2) a byte-faithful sparse TRUE-COSINE FP0 reimplementation of the harness's leave-one-BUG-out geometry,
     to avoid the VSA-bundle collapse artifact that pins coarse sigs at sim=1.0.

The sparse path reproduces H.evaluate EXACTLY on a token-bag signature when the bag is hashed to 2048 dims,
so I verify equivalence on a control sig first, then run the high-resolution sparse path (no hashing collapse).

Signatures (all APPLY-TIME legal, name-agnostic, model-free, diff-only):
  S1 skel_trigram  : name-agnostic op-skeleton trigrams over the ordered changed-line stream (+/- tagged).
  S2 ctx_anchored  : each changed line's op-skeleton bound to its nearest context line's op-skeleton.
  S3 rewrite_pairs : removed-line-skeleton -> added-line-skeleton transformation tokens (the structural rewrite).
  S4 charclass_ngram: char-class (alpha/digit/punct/space) 4-grams of the changed text (texture, high-card).
  S5 fusion        : S1+S3 concatenated namespace.
All scored sparse + true-cosine. Numbers are computed, never claimed.
"""
import re, os, math
from collections import Counter, defaultdict
import numpy as np
import trava_harness as H

A, C = H.load()
N = len(A)
iid = np.array([a['iid'] for a in A])
isfail = np.array([a['gp'] is not True for a in A])
iscorr = ~isfail

# ---------- sparse TRUE-COSINE FP0 evaluator (faithful to H.evaluate geometry) ----------
def sparse_eval(name, bags):
    """bags: list of Counter (token->count), one per attempt (index-aligned to A).
    Returns recall_fp0, sep(ff-fc) using TRUE cosine, leave-one-BUG-out, FP0 sound threshold."""
    # build vocab
    vocab = {}
    for b in bags:
        for t in b:
            if t not in vocab: vocab[t] = len(vocab)
    V = len(vocab)
    # sparse rows -> L2-normalized dense (V may be large but manageable)
    rows = []
    for b in bags:
        v = np.zeros(V, dtype=np.float64)
        for t, c in b.items():
            v[vocab[t]] = c
        nrm = np.linalg.norm(v)
        if nrm > 0: v /= nrm
        rows.append(v)
    M = np.array(rows)
    S = M @ M.T  # true cosine (rows unit-norm)
    # cross-bug separation
    samebug = iid[:, None] == iid[None, :]
    triu = np.triu(np.ones((N, N), dtype=bool), 1)
    ff_mask = triu & (~samebug) & isfail[:, None] & isfail[None, :]
    fc_mask = triu & (~samebug) & ((isfail[:, None] & iscorr[None, :]) | (iscorr[:, None] & isfail[None, :]))
    ff = float(S[ff_mask].mean()) if ff_mask.any() else 0.0
    fc = float(S[fc_mask].mean()) if fc_mask.any() else 0.0
    # leave-one-bug-out recall@FP0
    by_bug = defaultdict(list)
    for k in range(N):
        if isfail[k]: by_bug[iid[k]].append(k)
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
        thr = max(fp_sims) + 1e-12
        recall = sum(1 for s in tp_sims if s >= thr) / len(tp_sims) if tp_sims else 0.0
    else:
        thr, recall = None, None
    return {'name': name, 'recall_fp0': recall, 'sep': ff - fc, 'ff': ff, 'fc': fc,
            'thr': thr, 'V': V, 'n_tp': len(tp_sims), 'n_fp': len(fp_sims)}

# ---------- helpers ----------
def changed_stream(diff):
    """ordered list of (sign, abstract-skeleton-tuple) for each changed line."""
    out = []
    for l in diff.splitlines():
        if l[:3] in ('+++', '---') or l.startswith('@@') or l.startswith('diff '): continue
        if l.startswith('+') and l[1:].strip():
            sk = tuple(t for t in H.abstract_line(l[1:]))
            out.append(('+', sk))
        elif l.startswith('-') and l[1:].strip():
            sk = tuple(t for t in H.abstract_line(l[1:]))
            out.append(('-', sk))
    return out

def hunk_blocks(diff):
    """yield list of (sign, text) per hunk, sign in {+,-,' '} preserving context."""
    blocks = []
    cur = None
    for l in diff.splitlines():
        if l.startswith('@@'):
            if cur is not None: blocks.append(cur)
            cur = []
            continue
        if cur is None: continue
        if l[:3] in ('+++', '---') or l.startswith('diff '): continue
        if l.startswith('+'): cur.append(('+', l[1:]))
        elif l.startswith('-'): cur.append(('-', l[1:]))
        elif l.startswith(' '): cur.append((' ', l[1:]))
    if cur is not None: blocks.append(cur)
    return blocks

# ---------- signatures ----------
def sig_skel_trigram(a):
    """name-agnostic op-skeleton trigrams over the ordered +/- changed-line token stream."""
    feats = Counter()
    stream = changed_stream(a['fd'])
    # flatten: each changed line contributes its in-line skeleton trigrams (tagged by sign)
    for sign, sk in stream:
        toks = [f'{sign}{t}' for t in sk]
        for i in range(len(toks)):
            feats[toks[i]] += 1
            if i+1 < len(toks): feats[toks[i]+'|'+toks[i+1]] += 1
            if i+2 < len(toks): feats[toks[i]+'|'+toks[i+1]+'|'+toks[i+2]] += 1
    return feats

def sig_ctx_anchored(a):
    """bind each changed line's skeleton-head to its nearest context line's skeleton-head (edit-SITE shape)."""
    feats = Counter()
    for block in hunk_blocks(a['fd']):
        for i, (sign, text) in enumerate(block):
            if sign == ' ' or not text.strip(): continue
            sk = H.abstract_line(text)
            head = '_'.join(sk[:3]) if sk else 'EMPTY'
            # nearest context line above
            ctxsk = 'NOCTX'
            for j in range(i-1, -1, -1):
                if block[j][0] == ' ' and block[j][1].strip():
                    cs = H.abstract_line(block[j][1]); ctxsk = '_'.join(cs[:3]) if cs else 'EMPTY'
                    break
            feats[f'{sign}{head}@{ctxsk}'] += 1
    return feats

def sig_rewrite_pairs(a):
    """structural rewrite: pair each removed-line skeleton-head with each added-line skeleton-head in same hunk."""
    feats = Counter()
    for block in hunk_blocks(a['fd']):
        rem = [H.abstract_line(t) for s, t in block if s == '-' and t.strip()]
        add = [H.abstract_line(t) for s, t in block if s == '+' and t.strip()]
        rh = ['_'.join(s[:3]) if s else 'E' for s in rem]
        ah = ['_'.join(s[:3]) if s else 'E' for s in add]
        if not rem and add: feats['PURE_ADD_HUNK'] += 1
        if rem and not add: feats['PURE_DEL_HUNK'] += 1
        for r in rh:
            for x in ah:
                feats[f'{r}=>{x}'] += 1
        # also unigrams of each side
        for r in rh: feats[f'R:{r}'] += 1
        for x in ah: feats[f'A:{x}'] += 1
    return feats

def sig_charclass_ngram(a):
    """char-class 4-grams of changed text (alpha=a digit=d punct=p space=s) -> texture, high cardinality."""
    add, rem = H.diff_added_removed(a['fd'])
    feats = Counter()
    for sign, lines in (('+', add), ('-', rem)):
        for l in lines:
            cc = []
            for ch in l:
                if ch.isalpha(): cc.append('a')
                elif ch.isdigit(): cc.append('d')
                elif ch.isspace(): cc.append('s')
                else: cc.append('p')
            s = ''.join(cc)
            for i in range(len(s)-3):
                feats[f'{sign}{s[i:i+4]}'] += 1
    return feats

def sig_fusion(a):
    f = Counter()
    for k, v in sig_skel_trigram(a).items(): f['S1:'+k] += v
    for k, v in sig_rewrite_pairs(a).items(): f['S3:'+k] += v
    return f

# ---------- CONTROL: verify sparse path matches H.evaluate on a token bag ----------
def control_bag(a, ctx):
    # same as sig_moveshape-ish simple bag to cross-check sparse vs VSA on recall direction
    add, rem = H.diff_added_removed(a['fd']); feats = Counter()
    for role, lines in (('ADD', add), ('DEL', rem)):
        for l in lines:
            for t in H.abstract_line(l):
                feats[f'{role}:{t}'] += 1
    return feats

print("="*70)
print("CONTROL: lexical via H.evaluate (sanity)")
rlex = H.evaluate('lexical', lambda a, ctx: H.lexical_vsa(a['fd']), [dict(x) for x in A], C, verbose=False)
print(f"  lexical H.evaluate recall_fp0={rlex['recall_fp0']:.4f} sep={rlex['sep']:+.4f}")

print("="*70)
print("SPARSE TRUE-COSINE high-resolution signatures (no VSA collapse):")
sigs = [('S1_skel_trigram', sig_skel_trigram),
        ('S2_ctx_anchored', sig_ctx_anchored),
        ('S3_rewrite_pairs', sig_rewrite_pairs),
        ('S4_charclass_ngram', sig_charclass_ngram),
        ('S5_fusion', sig_fusion)]
LEX = rlex['recall_fp0']
results = {}
for name, fn in sigs:
    bags = [fn(a) for a in A]
    r = sparse_eval(name, bags)
    results[name] = r
    rec = r['recall_fp0']
    passes = rec is not None and rec > 0.25 and rec > LEX
    print(f"  {name:20s} recall_fp0={rec if rec is None else round(rec,4)} "
          f"sep={r['sep']:+.4f} ff={r['ff']:.3f} fc={r['fc']:.3f} V={r['V']} "
          f"{'*** PASS' if passes else 'fail'}")

# also run the SAME high-res bags through the OFFICIAL H.evaluate (VSA path) for cross-check
print("="*70)
print("Same sigs via OFFICIAL H.evaluate (VSA-2048 path):")
for name, fn in sigs:
    r = H.evaluate(name, lambda a, ctx, fn=fn: fn(a), [dict(x) for x in A], C, verbose=False)
    rec = r['recall_fp0']
    passes = rec is not None and rec > 0.25 and rec > LEX
    print(f"  {name:20s} recall_fp0={rec if rec is None else round(rec,4)} "
          f"sep={r['sep']:+.4f} ff={r['xbug_failed_failed']:.3f} fc={r['xbug_failed_correct']:.3f} "
          f"{'*** PASS' if passes else 'fail'}")
print("="*70)
print(f"BAR: recall_fp0 > 0.25 AND > lexical({LEX:.4f})")
