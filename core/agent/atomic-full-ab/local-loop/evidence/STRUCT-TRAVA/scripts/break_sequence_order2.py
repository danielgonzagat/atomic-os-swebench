#!/usr/bin/env python3
"""sequence_order — refinement pass. Same angle (ordered op-sequence shape), tuning the op alphabet,
n-gram order, and a zone-bucketed positional binding (start/mid/end of the edit). All model-free,
APPLY-TIME legal (diff only). Every number from H.evaluate; nothing claimed.
"""
import numpy as np
import trava_harness as H

A, C = H.load()
D = H.D

def op_class_mid(line):
    ab = H.abstract_line(line)
    if not ab: return None
    skel = tuple(t for t in ab if (t in H.PYKW or not (t == 'ID' or t == 'NUM' or t == 'STR')))
    return skel if skel else ('EMPTY',)

def op_sequence(diff):
    seq = []
    for l in diff.splitlines():
        if l[:3] in ('+++', '---') or l.startswith('diff '): continue
        if l.startswith('@@'):
            seq.append('HUNK'); continue
        if l.startswith('+') and l[1:].strip():
            oc = op_class_mid(l[1:])
            if oc: seq.append(('+', oc))
        elif l.startswith('-') and l[1:].strip():
            oc = op_class_mid(l[1:])
            if oc: seq.append(('-', oc))
    return seq

def zone(i, n):
    if n <= 1: return 'Z'
    f = i / (n - 1)
    return 'Zs' if f < 0.34 else ('Zm' if f < 0.67 else 'Ze')

def encode(seq, n=3, use_zone=True, use_len=True, skip=False):
    """ordered op-sequence shape: relative-order n-grams up to n, optionally zone-bucketed."""
    if not seq:
        return [0] * D
    parts = []
    L = len(seq)
    for k in range(1, n + 1):
        for i in range(L - k + 1):
            gram = tuple(seq[i:i + k])
            key = (k, gram, zone(i, L)) if use_zone else (k, gram)
            parts.append(np.array(H.atom('SO2:' + str(key)), dtype=np.float32))
    if skip:  # relative-order skip-bigrams (i, i+2) — captures order across a gap
        for i in range(L - 2):
            key = ('sk', (seq[i], seq[i + 2]))
            parts.append(np.array(H.atom('SO2:' + str(key)), dtype=np.float32))
    if use_len:
        lb = min(L // 4, 12)
        parts.append(np.array(H.atom('SO2:LENBKT:' + str(lb)), dtype=np.float32) * 1.0)
    acc = np.sum(parts, axis=0)
    return np.where(acc >= 0, 1, -1).astype(np.int8).tolist()

def mk(**kw):
    return lambda a, ctx: encode(op_sequence(a['fd']), **kw)

CANDS = [
    ('mid/ng3/nozone/nolen',       mk(n=3, use_zone=False, use_len=False)),
    ('mid/ng3/zone',               mk(n=3, use_zone=True,  use_len=False)),
    ('mid/ng3/zone+len',           mk(n=3, use_zone=True,  use_len=True)),
    ('mid/ng3/nozone+len',         mk(n=3, use_zone=False, use_len=True)),
    ('mid/ng4/nozone/nolen',       mk(n=4, use_zone=False, use_len=False)),
    ('mid/ng4/zone',               mk(n=4, use_zone=True,  use_len=False)),
    ('mid/ng4/nozone+len',         mk(n=4, use_zone=False, use_len=True)),
    ('mid/ng3/nozone+skip',        mk(n=3, use_zone=False, use_len=False, skip=True)),
    ('mid/ng3/zone+len+skip',      mk(n=3, use_zone=True,  use_len=True,  skip=True)),
    ('mid/ng2/zone+len',           mk(n=2, use_zone=True,  use_len=True)),
    ('mid/ng5/nozone/nolen',       mk(n=5, use_zone=False, use_len=False)),
]

lex = H.evaluate('LEX', lambda a, ctx: H.lexical_vsa(a['fd']),
                 [dict(x) for x in A], C, True, False)
LEX = lex['recall_fp0']
print(f"{'candidate':30s} {'recall@FP0':>11s} {'sep':>8s} {'ff':>7s} {'fc':>7s}  verdict")
print('-' * 80)
print(f"{'LEXICAL':30s} {LEX:11.3f}")
best = None
for name, fn in CANDS:
    r = H.evaluate(name, fn, [dict(x) for x in A], C, True, False)
    rec = r['recall_fp0'] or 0.0
    p = rec > 0.25 and rec > LEX
    if best is None or rec > best[1]:
        best = (name, rec, r)
    print(f"{name:30s} {rec:11.3f} {r['sep']:+8.3f} {r['xbug_failed_failed']:7.3f} "
          f"{r['xbug_failed_correct']:7.3f}  {'*** PASS' if p else 'fail'}")
print('-' * 80)
bn, brec, br = best
print(f"BEST: {bn}  recall@FP0={brec:.4f}  PASS_BAR={brec>0.25 and brec>0.126}")
print(f"BEST_FULL={ {k:br[k] for k in ('name','recall_fp0','sep','xbug_failed_failed','xbug_failed_correct','thr','n_failed','n_correct','n_bugs')} }")
