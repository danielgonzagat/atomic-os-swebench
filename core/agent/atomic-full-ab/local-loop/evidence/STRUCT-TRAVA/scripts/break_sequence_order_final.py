#!/usr/bin/env python3
"""ANGLE: sequence_order (FINAL, honest).

Encode the ORDERED sequence of abstracted edit operations as a SHAPE (not a bag):
  - op alphabet = the keyword/operator SKELETON of each changed line (H.abstract_line with ID/NUM/STR
    fillers dropped), tagged by +/- and HUNK boundaries -> a name-AGNOSTIC ordered op-sequence.
  - ORDER captured via relative-order n-grams (k=1..n) of that sequence, VSA-bundled. Two edits doing the
    same ops in the same order collapse; reorder/substitute an op breaks the match.
Model-free, deterministic, APPLY-TIME legal (diff only; no gold/iid/problem/traceback).

VERDICT IS A NULL, established by a SEED-ROBUSTNESS audit:
  The VSA atom dictionary is a random sign-projection. The seed (== the atom-key string prefix) is a
  nuisance parameter that MUST NOT change a real structural signal. The single best default-seed config
  (n=4) reaches recall_fp0=0.3075 (> 0.25, > lexical 0.126) -- but that is a random-projection hash-
  collision artifact: re-seeding the SAME encoder yields 0.063..0.259 (mean ~0.158). No seed robustly
  clears 0.25. Reported headline = the seed-robust MEAN; the 0.3075 is logged as the lucky-seed ceiling.
"""
import numpy as np, hashlib, random
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

def atom_salted(t, salt):
    h = hashlib.sha256((salt + ':' + str(t)).encode()).digest()
    st = random.getstate(); random.seed(int.from_bytes(h, 'big'))
    v = np.array([random.choice([1, -1]) for _ in range(D)], dtype=np.float32)
    random.setstate(st)
    return v

def encode(diff, n=4, salt='SO2'):
    seq = op_sequence(diff)
    if not seq: return [0] * D
    parts, L = [], len(seq)
    for k in range(1, n + 1):
        for i in range(L - k + 1):
            parts.append(atom_salted((k, tuple(seq[i:i + k])), salt))
    acc = np.sum(parts, axis=0)
    return np.where(acc >= 0, 1, -1).astype(np.int8).tolist()

LEX = H.evaluate('LEX', lambda a, ctx: H.lexical_vsa(a['fd']), [dict(x) for x in A], C, True, False)['recall_fp0']

# headline config n=4, default-seed ceiling (the prefix string IS the seed):
def enc_default(a, ctx):
    seq = op_sequence(a['fd'])
    if not seq: return [0] * D
    parts, L = [], len(seq)
    for k in range(1, 5):
        for i in range(L - k + 1):
            parts.append(np.array(H.atom('SO2:' + str((k, tuple(seq[i:i + k])))), dtype=np.float32))
    return np.where(np.sum(parts, axis=0) >= 0, 1, -1).astype(np.int8).tolist()
CEIL = H.evaluate('seqorder/mid/ng4 (lucky-seed ceiling)', enc_default, [dict(x) for x in A], C, True, False)

# seed-robustness band (6 independent random projections of the IDENTICAL encoder):
recs = []
for s in ['SO2', 'SALT-alpha', 'SALT-bravo', 'SALT-charlie', 'SALT-delta', 'SALT-echo']:
    r = H.evaluate('seed/' + s, lambda a, ctx, s=s: encode(a['fd'], 4, s), [dict(x) for x in A], C, True, False)
    recs.append(r['recall_fp0'] or 0.0)
recs = np.array(recs)
ROBUST_MEAN = float(recs.mean())

print('=== sequence_order: ordered op-sequence SHAPE (VSA), model-free, applytime-legal ===')
print(f"lexical baseline recall_fp0            = {LEX:.4f}")
print(f"lucky-seed ceiling (n=4, default salt) = {CEIL['recall_fp0']:.4f}   sep={CEIL['sep']:+.4f}  "
      f"ff={CEIL['xbug_failed_failed']:.4f} fc={CEIL['xbug_failed_correct']:.4f}")
print(f"seed-robustness band over 6 seeds      = {recs.round(4).tolist()}")
print(f"  mean={recs.mean():.4f} min={recs.min():.4f} max={recs.max():.4f} std={recs.std():.4f}")
print(f"  any seed >0.25 ?  {(recs>0.25).any()}   ALL seeds >0.25 ? {(recs>0.25).all()}")
print()
print(f"HEADLINE recall_fp0 (seed-robust mean) = {ROBUST_MEAN:.4f}")
print(f"separation (ff-fc, lucky seed)         = {CEIL['sep']:+.4f}")
print(f"PASS_BAR (robust mean >0.25 AND >0.126)= {ROBUST_MEAN>0.25 and ROBUST_MEAN>0.126}")
print(f"VERDICT = NULL (beats lexical on average, fails the 0.25 bar; the single passing config is a "
      f"random-projection artifact that does not survive re-seeding).")
