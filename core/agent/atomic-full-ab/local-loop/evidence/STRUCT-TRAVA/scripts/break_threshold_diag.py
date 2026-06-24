#!/usr/bin/env python3
"""Diagnose WHY recall_fp0=0 even when sep>0: is the FP0 threshold poisoned by a few correct outliers?
Also test the strongest sep signal (U5) under a SOFTER but still honest soundness rule:
  recall@FP<=k for small k (block at most k held-out correct moves total) -- reports how recall climbs as we
  permit a tiny, explicit number of correct-blocks. recall_fp0 (k=0) is the BAR; this shows the SHAPE of the wall."""
import re, io, tokenize
from collections import Counter, defaultdict
import numpy as np
import trava_harness as H

A, C = H.load()
D = H.D

_STOP = set('the a an of to in is be on for and or not this that with as by from at it if def class self return'.split())
def _idents(line):
    out = []
    try:
        for tok in tokenize.generate_tokens(io.StringIO(line).readline):
            if tok.type == tokenize.NAME and tok.string not in H.PYKW: out.append(tok.string)
    except Exception:
        out = [w for w in re.findall(r'[A-Za-z_]\w*', line) if w not in H.PYKW]
    return out
def sig_problem_edit_bind(a, ctx):
    ps = (ctx['problem'].get(a['iid'], '') or '').lower()
    pwords = set(w for w in re.findall(r'[a-z_]{3,}', ps) if w not in _STOP)
    add, rem = H.diff_added_removed(a['fd'])
    add_ids = set(i.lower() for l in add for i in _idents(l))
    on = add_ids & pwords; off = add_ids - pwords
    feats = Counter(); tot = len(add_ids) + 1
    feats[f'ONTOPIC_{round(len(on)/tot,1)}'] += 1
    feats[f'NON_{min(len(off),6)}'] += 1
    add_text = ' '.join(add).lower()
    for kw in ('error','exception','none','empty','raise','default','missing','attribute','type','value','key','index'):
        if kw in ps and kw in add_text: feats['BOTH:'+kw] += 1
    return feats

def recall_at_k(encode_fn):
    Acpy = [dict(x) for x in A]
    for a in Acpy:
        r = encode_fn(a, C)
        if r and isinstance(r, list) and len(r) == D: a['_v'] = r
        else: a['_v'] = H.encode_tokens(r)
    M = np.array([a['_v'] for a in Acpy], dtype=np.float64)
    S = np.nan_to_num((M @ M.T) / D)
    iid = np.array([a['iid'] for a in Acpy])
    isfail = np.array([a['gp'] is not True for a in Acpy]); iscorr = ~isfail
    N = len(Acpy)
    by_bug = defaultdict(list)
    for k, a in enumerate(Acpy):
        if a['gp'] is not True: by_bug[a['iid']].append(k)
    bugs = [b for b, v in by_bug.items() if len(v) >= 2]
    tp_sims, fp_sims = [], []
    for held in bugs:
        bank = np.array([k for k in range(N) if isfail[k] and iid[k] != held])
        if bank.size == 0: continue
        for t in [k for k in range(N) if isfail[k] and iid[k] == held]: tp_sims.append(float(S[t, bank].max()))
        for c in [k for k in range(N) if iscorr[k] and iid[k] == held]: fp_sims.append(float(S[c, bank].max()))
    tp = np.array(sorted(tp_sims, reverse=True)); fp = np.array(sorted(fp_sims, reverse=True))
    print(f'  n_held_fail(TP candidates)={len(tp)}  n_held_corr(FP candidates)={len(fp)}')
    print(f'  top correct-move similarities to failed bank: {np.round(fp[:6],3).tolist()}')
    # recall at allowing the k-th highest correct (FP=k means threshold just below k-th correct)
    for k in range(0, 6):
        if k >= len(fp): break
        thr = fp[k] + 1e-9   # block all correct with sim>fp[k]; k correct blocked
        rec = float((tp >= thr).mean())
        print(f'    FP={k} (thr={thr:.3f}): recall_failed={rec:.3f}')

print('=== U5 problem_edit_bind: threshold-wall shape ===')
recall_at_k(sig_problem_edit_bind)
print('=== LEXICAL baseline: threshold-wall shape ===')
recall_at_k(lambda a, ctx: H.lexical_vsa(a['fd']))
