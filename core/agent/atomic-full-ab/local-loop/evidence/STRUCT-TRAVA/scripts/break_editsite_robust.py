#!/usr/bin/env python3
"""Push the ONE direction with positive cross-bug separation (edit-SITE context shape, ff>fc):
 (1) seed-robustness of the VSA 'wins' (S2 0.167, S4 0.201) across 6 seeds -> are they random-projection luck?
 (2) a richer high-resolution edit-site signature (context window skeletons, both sides) via true sparse cosine.
 (3) k-NN density scoring (mean top-k bank neighbours) on the best positive-sep sig -> does density beat 1-NN?
Numbers computed via H.evaluate (seed-swept) and the byte-faithful sparse FP0 reimpl. Never claimed.
"""
import re, hashlib, random
from collections import Counter, defaultdict
import numpy as np
import trava_harness as H

A, C = H.load()
N = len(A)
iid = np.array([a['iid'] for a in A])
isfail = np.array([a['gp'] is not True for a in A])
iscorr = ~isfail
LEX = 0.12643678160919541

def hunk_blocks(diff):
    blocks, cur = [], None
    for l in diff.splitlines():
        if l.startswith('@@'):
            if cur is not None: blocks.append(cur)
            cur = []; continue
        if cur is None: continue
        if l[:3] in ('+++', '---') or l.startswith('diff '): continue
        if l.startswith('+'): cur.append(('+', l[1:]))
        elif l.startswith('-'): cur.append(('-', l[1:]))
        elif l.startswith(' '): cur.append((' ', l[1:]))
    if cur is not None: blocks.append(cur)
    return blocks

# --- richer edit-site sig: each changed line bound to a WINDOW of context skeletons above+below ---
def sig_editsite_rich(a):
    feats = Counter()
    for block in hunk_blocks(a['fd']):
        for i, (sign, text) in enumerate(block):
            if sign == ' ' or not text.strip(): continue
            sk = H.abstract_line(text); head = '_'.join(sk[:4]) if sk else 'E'
            above = below = 'NO'
            for j in range(i-1, -1, -1):
                if block[j][0] == ' ' and block[j][1].strip():
                    cs = H.abstract_line(block[j][1]); above = '_'.join(cs[:4]) if cs else 'E'; break
            for j in range(i+1, len(block)):
                if block[j][0] == ' ' and block[j][1].strip():
                    cs = H.abstract_line(block[j][1]); below = '_'.join(cs[:4]) if cs else 'E'; break
            feats[f'{sign}{head}'] += 1
            feats[f'{sign}[{above}|{below}]'] += 1
            feats[f'{sign}{head}@{above}'] += 1
    return feats

def sig_editsite_basic(a):  # the S2 that gave +sep
    feats = Counter()
    for block in hunk_blocks(a['fd']):
        for i, (sign, text) in enumerate(block):
            if sign == ' ' or not text.strip(): continue
            sk = H.abstract_line(text); head = '_'.join(sk[:3]) if sk else 'EMPTY'
            ctxsk = 'NOCTX'
            for j in range(i-1, -1, -1):
                if block[j][0] == ' ' and block[j][1].strip():
                    cs = H.abstract_line(block[j][1]); ctxsk = '_'.join(cs[:3]) if cs else 'EMPTY'; break
            feats[f'{sign}{head}@{ctxsk}'] += 1
    return feats

def sparse_S(bags):
    vocab = {}
    for b in bags:
        for t in b:
            if t not in vocab: vocab[t] = len(vocab)
    V = len(vocab)
    M = np.zeros((N, V))
    for k, b in enumerate(bags):
        for t, c in b.items(): M[k, vocab[t]] = c
    nrm = np.linalg.norm(M, axis=1, keepdims=True); nrm[nrm == 0] = 1
    M = M / nrm
    return M @ M.T, V

def fp0_recall(S, knn=1):
    by_bug = defaultdict(list)
    for k in range(N):
        if isfail[k]: by_bug[iid[k]].append(k)
    bugs = [b for b, v in by_bug.items() if len(v) >= 2]
    tp, fp = [], []
    for held in bugs:
        bank = np.array([k for k in range(N) if isfail[k] and iid[k] != held])
        if bank.size == 0: continue
        def score(t):
            sims = np.sort(S[t, bank])[::-1]
            return float(sims[:knn].mean())
        for t in [k for k in range(N) if isfail[k] and iid[k] == held]: tp.append(score(t))
        for c in [k for k in range(N) if iscorr[k] and iid[k] == held]: fp.append(score(c))
    if not fp: return None
    thr = max(fp) + 1e-12
    return sum(1 for s in tp if s >= thr) / len(tp) if tp else 0.0

# (1) seed-robustness of VSA path for S2 and S4
print("="*70); print("(1) SEED-ROBUSTNESS of the VSA 'near-miss' wins (are they projection luck?)")
def sig_charclass(a, ctx):
    add, rem = H.diff_added_removed(a['fd']); feats = Counter()
    for sign, lines in (('+', add), ('-', rem)):
        for l in lines:
            cc = ''.join('a' if c.isalpha() else 'd' if c.isdigit() else 's' if c.isspace() else 'p' for c in l)
            for i in range(len(cc)-3): feats[f'{sign}{cc[i:i+4]}'] += 1
    return feats
for label, fn in [('S2_ctx_anchored', lambda a, ctx: sig_editsite_basic(a)),
                  ('S4_charclass', sig_charclass)]:
    recs = []
    for seed in range(6):
        H._AC.clear(); H._CC.clear()
        # perturb atom hashing by salting the prefix via global seed trick: re-seed atom cache deterministically
        # we emulate a different random projection by monkeypatching atom prefix
        orig_atom = H.atom
        def atom_seeded(t, s=seed, oa=orig_atom):
            key = (s, t)
            if key not in H._AC:
                h = hashlib.sha256((f'A{s}:' + str(t)).encode()).digest(); st = random.getstate()
                random.seed(int.from_bytes(h, 'big')); H._AC[key] = [random.choice([1, -1]) for _ in range(H.D)]
                random.setstate(st)
            return H._AC[key]
        H.atom = atom_seeded
        r = H.evaluate(label, fn, [dict(x) for x in A], C, verbose=False)
        H.atom = orig_atom
        recs.append(r['recall_fp0'])
    print(f"  {label:18s} seeds={[round(x,3) for x in recs]} mean={np.mean(recs):.3f} std={np.std(recs):.3f} "
          f"cross-0.25={sum(x>0.25 for x in recs)}/6")

# (2) richer edit-site via TRUE sparse cosine (no projection luck)
print("="*70); print("(2) RICHER edit-site, TRUE sparse cosine (honest, no VSA collapse/luck):")
for name, fn in [('editsite_basic', sig_editsite_basic), ('editsite_rich', sig_editsite_rich)]:
    bags = [fn(a) for a in A]
    S, V = sparse_S(bags)
    # sep
    samebug = iid[:, None] == iid[None, :]; triu = np.triu(np.ones((N, N), bool), 1)
    ff = S[triu & (~samebug) & isfail[:, None] & isfail[None, :]].mean()
    fc = S[triu & (~samebug) & ((isfail[:, None] & iscorr[None, :]) | (iscorr[:, None] & isfail[None, :]))].mean()
    rec = fp0_recall(S, knn=1)
    print(f"  {name:16s} recall_fp0={rec if rec is None else round(rec,4)} sep={ff-fc:+.4f} ff={ff:.4f} fc={fc:.4f} V={V} "
          f"{'PASS' if rec and rec>0.25 and rec>LEX else 'fail'}")

# (3) k-NN density scoring on best positive-sep sig
print("="*70); print("(3) k-NN DENSITY scoring on editsite_rich (does mean-top-k beat 1-NN?):")
bags = [sig_editsite_rich(a) for a in A]; S, _ = sparse_S(bags)
for k in (1, 3, 5, 10):
    rec = fp0_recall(S, knn=k)
    print(f"  top-{k:<2d} recall_fp0={rec if rec is None else round(rec,4)} {'PASS' if rec and rec>0.25 and rec>LEX else 'fail'}")
print("="*70); print(f"BAR: recall_fp0 > 0.25 AND > lexical({LEX:.4f})")
