#!/usr/bin/env python3
"""AUDIT of the winner sequence_order/mid/ng4/nozone/nolen.
Checks:
  (1) leak audit: encoder uses ONLY the diff (no gold, no iid). Print the inputs it reads.
  (2) seed-robustness: re-hash the atom dictionary with N alternative salts; recompute recall_fp0 each time.
      A real signal survives the random projection; an artifact of one lucky hash collapses.
  (3) n-robustness: recall_fp0 across n in {3,4,5,6}.
  (4) degeneracy check (the tb_relation trap): how many DISTINCT vectors? how many attempts collapse
      to the single most-common vector? (the +0.511-sep artifact was 321/376 collapsing to NO_TRACEBACK.)
  (5) print the threshold-setting (poison) correct move and its nearest failed neighbor — sanity that the
      SOUND-trava property holds and recall is real held-out blocking.
"""
import numpy as np, hashlib, random
import trava_harness as H
from collections import Counter, defaultdict

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

def encode(seq, n=4, salt='SO2'):
    if not seq: return [0] * D
    parts = []
    L = len(seq)
    for k in range(1, n + 1):
        for i in range(L - k + 1):
            parts.append(atom_salted((k, tuple(seq[i:i + k])), salt))
    acc = np.sum(parts, axis=0)
    return np.where(acc >= 0, 1, -1).astype(np.int8).tolist()

# ---- (1) leak audit ----
print('=== (1) LEAK AUDIT ===')
print('encoder reads: attempt["fd"] (the unified diff) ONLY.')
print('NOT used: attempt["iid"], attempt["gp"], ctx["gold_files"], ctx["gold_syms"], ctx["problem"], ctx["tb_frames"].')
print('=> APPLY-TIME legal (a real trava computable before knowing the answer).')

# ---- (2) seed robustness ----
print('\n=== (2) SEED ROBUSTNESS (recall_fp0 under 6 independent random projections) ===')
recs = []
for s in ['SO2', 'SALT-alpha', 'SALT-bravo', 'SALT-charlie', 'SALT-delta', 'SALT-echo']:
    fn = lambda a, ctx, s=s: encode(op_sequence(a['fd']), n=4, salt=s)
    r = H.evaluate('seed/' + s, fn, [dict(x) for x in A], C, True, False)
    recs.append(r['recall_fp0'] or 0.0)
    print(f"  salt={s:13s} recall_fp0={r['recall_fp0']:.4f} sep={r['sep']:+.4f}")
print(f"  -> mean={np.mean(recs):.4f}  min={min(recs):.4f}  max={max(recs):.4f}  std={np.std(recs):.4f}")
print(f"  -> ALL beat 0.25? {all(x>0.25 for x in recs)}   ALL beat lexical 0.126? {all(x>0.126 for x in recs)}")

# ---- (3) n robustness ----
print('\n=== (3) n-ROBUSTNESS ===')
for n in (2, 3, 4, 5, 6):
    fn = lambda a, ctx, n=n: encode(op_sequence(a['fd']), n=n, salt='SO2')
    r = H.evaluate(f'n={n}', fn, [dict(x) for x in A], C, True, False)
    print(f"  n={n}  recall_fp0={r['recall_fp0']:.4f}  sep={r['sep']:+.4f}")

# ---- (4) degeneracy check ----
print('\n=== (4) DEGENERACY CHECK (no NO_TRACEBACK-style collapse) ===')
vecs = [tuple(encode(op_sequence(a['fd']), 4, 'SO2')) for a in A]
cnt = Counter(vecs)
print(f"  distinct vectors: {len(cnt)} / {len(A)} attempts")
mc, mn = cnt.most_common(1)[0]
print(f"  largest collapse group: {mn} attempts share one vector ({100*mn/len(A):.1f}%)")
zero = sum(1 for v in vecs if all(x == 0 for x in v))
print(f"  all-zero (empty-seq) vectors: {zero}")

# ---- (5) sound-trava sanity: the poison correct move + threshold mechanics ----
print('\n=== (5) SOUND-TRAVA SANITY (poison correct move + held-out blocking is REAL) ===')
for a in A: a['_v'] = encode(op_sequence(a['fd']), 4, 'SO2')
M = np.array([a['_v'] for a in A], dtype=np.float64)
S = np.nan_to_num((M @ M.T) / D)
iid = np.array([a['iid'] for a in A]); isfail = np.array([a['gp'] is not True for a in A])
N = len(A)
by_bug = defaultdict(list)
for k, a in enumerate(A):
    if a['gp'] is not True: by_bug[a['iid']].append(k)
bugs = [b for b, v in by_bug.items() if len(v) >= 2]
fp_sims = []; poison = None
for held in bugs:
    bank = np.array([k for k in range(N) if isfail[k] and iid[k] != held])
    held_corr = [k for k in range(N) if (not isfail[k]) and iid[k] == held]
    for c in held_corr:
        s = float(S[c, bank].max())
        fp_sims.append(s)
        if poison is None or s > poison[0]:
            j = bank[int(np.argmax(S[c, bank]))]
            poison = (s, A[c]['iid'], A[j]['iid'])
thr = max(fp_sims) + 1e-9
tp = []
for held in bugs:
    bank = np.array([k for k in range(N) if isfail[k] and iid[k] != held])
    for t in [k for k in range(N) if isfail[k] and iid[k] == held]:
        tp.append(float(S[t, bank].max()))
recall = sum(1 for s in tp if s >= thr) / len(tp)
print(f"  threshold thr={thr:.4f} (set by held-out CORRECT move of bug={poison[1]} -> nearest bank-fail bug={poison[2]} sim={poison[0]:.4f})")
print(f"  held-out FAILED moves blocked: {sum(1 for s in tp if s>=thr)}/{len(tp)} = recall_fp0={recall:.4f}")
print(f"  held-out CORRECT moves blocked: 0 (by construction thr=max(fp_sims)+eps) -> SOUND trava preserved")
print(f"\n  FINAL recall_fp0={recall:.4f}  PASS_BAR={recall>0.25 and recall>0.126}")
