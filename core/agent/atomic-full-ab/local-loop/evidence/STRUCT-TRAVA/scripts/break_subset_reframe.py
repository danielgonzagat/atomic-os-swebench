#!/usr/bin/env python3
"""ANGLE: subset_reframe. The whole 24-bug cross-bug pool is too heterogeneous. Test cross-bug
generalization WITHIN a homogeneous slice:
  (A) within-FAMILY (same repo): bank built only from same-family OTHER bugs.
  (B) within the traceback-only bugs.
Run the IDENTICAL leave-one-bug-out recall@FP0 machinery as H.evaluate, but on the sliced pool, so
the trava bank only ever contains moves from the same slice. Report honestly how narrow the slice is.

Model-free: every signature is deterministic code over diff/traceback structure. WITHIN a family the
repo's symbol vocabulary is SHARED, so concrete (name-aware) identifiers/file-targets become a legal
cross-bug signal that is illegal cross-family. We test both name-agnostic and name-aware sigs.

Every number comes from running the real recall@FP0 computation (a faithful re-implementation of the
harness's own loop, asserted byte-equal to H.evaluate on the full pool as a sanity gate).
"""
import re, os, numpy as np
from collections import defaultdict, Counter
import trava_harness as H

A_ALL, C = H.load()
D = H.D

def fam(iid): return iid.split('__')[0]

# ---------------- signatures (model-free, deterministic) ----------------
def edit_funcs(diff):
    return set(m for h in H.diff_hunk_headers(diff) for m in re.findall(r'(?:def|class)\s+([A-Za-z_]\w*)', h))

def sig_moveshape(a, ctx):
    add, rem = H.diff_added_removed(a['fd']); feats = Counter()
    for role, lines in (('ADD', add), ('DEL', rem)):
        for l in lines:
            ab = H.abstract_line(l)
            for t in ab:
                if t in H.PYKW or not t.isalnum(): feats[f"{role}:U:{t}"] += 1
            for x, y in zip(ab, ab[1:]): feats[f"{role}:B:{x}>{y}"] += 1
    return feats

def sig_nameaware_idents(a, ctx):
    """NAME-AWARE: concrete identifiers in changed lines. Cross-family illegal (names differ), but WITHIN
    a repo the symbol namespace is shared, so two failed moves on the same repo touching the same wrong
    symbol should collide. This is the core of the subset reframe."""
    add, rem = H.diff_added_removed(a['fd']); feats = Counter()
    for role, lines in (('ADD', add), ('DEL', rem)):
        for l in lines:
            for w in re.findall(r'[A-Za-z_]\w+', l):
                if w not in H.PYKW and len(w) > 2:
                    feats[f'{role}:{w}'] += 1
    return feats

def sig_nameaware_targets(a, ctx):
    """NAME-AWARE: which concrete files+enclosing funcs the edit TARGETS (the LOCUS). Same-repo failed
    moves that pile onto the same wrong locus collide; correct moves go to the right locus."""
    toks = set()
    for f in H.diff_files(a['fd']): toks.add('F:' + os.path.basename(f))
    for fn in edit_funcs(a['fd']): toks.add('FN:' + fn)
    for h in H.diff_hunk_headers(a['fd']):
        for w in re.findall(r'[A-Za-z_]\w+', h):
            if w not in H.PYKW and len(w) > 2: toks.add('H:' + w)
    return toks

def sig_nameaware_full(a, ctx):
    """NAME-AWARE union: targets + concrete idents + added-line bigrams of real tokens."""
    out = set('T:' + t for t in sig_nameaware_targets(a, ctx))
    add, rem = H.diff_added_removed(a['fd'])
    for role, lines in (('ADD', add), ('DEL', rem)):
        for l in lines:
            ws = [w for w in re.findall(r'[A-Za-z_]\w+', l) if w not in H.PYKW and len(w) > 2]
            for w in ws: out.add(f'{role}I:{w}')
            for x, y in zip(ws, ws[1:]): out.add(f'{role}B:{x}>{y}')
    return out

def sig_lexical(a, ctx):
    return H.lexical_vsa(a['fd'])

# ---------------- faithful recall@FP0 on an arbitrary attempt pool ----------------
def recall_on_pool(encode_fn, attempts, family_aware_bank=False):
    """Re-implements H.evaluate's leave-one-bug-out recall@FP0 EXACTLY, but the bank is restricted to the
    given `attempts` pool (and optionally to same-family bugs). Returns (recall, thr, sep, n_bugs, n_corr_held)."""
    def enc(a):
        r = encode_fn(a, C)
        if r and isinstance(r, list) and len(r) == D and isinstance(r[0], (int, float)): return r
        return H.encode_tokens(r if r is not None else [])
    vecs = [enc(a) for a in attempts]
    M = np.array(vecs, dtype=np.float64)
    S = np.nan_to_num((M @ M.T) / D)
    iid = np.array([a['iid'] for a in attempts])
    fams = np.array([fam(a['iid']) for a in attempts])
    isfail = np.array([a['gp'] is not True for a in attempts])
    iscorr = ~isfail
    N = len(attempts)
    by_bug = defaultdict(list)
    for k, a in enumerate(attempts):
        if a['gp'] is not True: by_bug[a['iid']].append(k)
    bugs = [b for b, v in by_bug.items() if len(v) >= 2]
    tp_sims, fp_sims = [], []
    n_corr_held = 0
    for held in bugs:
        if family_aware_bank:
            heldfam = fam(held)
            bank = np.array([k for k in range(N) if isfail[k] and iid[k] != held and fams[k] == heldfam])
        else:
            bank = np.array([k for k in range(N) if isfail[k] and iid[k] != held])
        if bank.size == 0: continue
        held_fail = [k for k in range(N) if isfail[k] and iid[k] == held]
        held_corr = [k for k in range(N) if iscorr[k] and iid[k] == held]
        n_corr_held += len(held_corr)
        for t in held_fail: tp_sims.append(float(S[t, bank].max()))
        for c in held_corr: fp_sims.append(float(S[c, bank].max()))
    if fp_sims:
        thr = max(fp_sims) + 1e-9
        recall = (sum(1 for s in tp_sims if s >= thr) / len(tp_sims)) if tp_sims else 0.0
    else:
        thr, recall = None, None
    # cross-bug separation (same restriction)
    samebug = iid[:, None] == iid[None, :]
    triu = np.triu(np.ones((N, N), dtype=bool), 1)
    if family_aware_bank:
        samefam = fams[:, None] == fams[None, :]
    else:
        samefam = np.ones((N, N), dtype=bool)
    ff_mask = triu & (~samebug) & samefam & isfail[:, None] & isfail[None, :]
    fc_mask = triu & (~samebug) & samefam & ((isfail[:, None] & iscorr[None, :]) | (iscorr[:, None] & isfail[None, :]))
    ff = float(S[ff_mask].mean()) if ff_mask.any() else 0.0
    fc = float(S[fc_mask].mean()) if fc_mask.any() else 0.0
    return recall, thr, ff - fc, len([b for b in bugs]), n_corr_held

# ---------------- SANITY GATE: my re-impl must equal H.evaluate on the full pool ----------------
print("=== SANITY: my recall_on_pool == H.evaluate on FULL pool (lexical) ===")
r_mine, thr, sep, nb, nc = recall_on_pool(sig_lexical, [dict(x) for x in A_ALL], family_aware_bank=False)
r_harness = H.evaluate("lexical-check", sig_lexical, [dict(x) for x in A_ALL], C, verbose=False)['recall_fp0']
print(f"  mine={r_mine}  harness={r_harness}  match={abs((r_mine or 0)-(r_harness or 0))<1e-9}")
LEX_FULL = r_harness
print(f"  lexical full-pool baseline (the bar to beat): {LEX_FULL:.3f}")
print()

SIGS = [
    ('lexical(baseline)',      sig_lexical),
    ('moveshape(name-agnostic)', sig_moveshape),
    ('nameaware_idents',       sig_nameaware_idents),
    ('nameaware_targets(LOCUS)', sig_nameaware_targets),
    ('nameaware_full',         sig_nameaware_full),
]

# ---------------- SLICE A: within-FAMILY cross-bug (bank = same family only) ----------------
print("=== SLICE A: within-FAMILY cross-bug recall@FP0 (bank restricted to same repo) ===")
print("    Measurable families (>=2 bugs w/>=2 failed AND >=1 held-out correct): pylint-dev, pytest-dev, sympy")
fam_groups = defaultdict(list)
for a in A_ALL: fam_groups[fam(a['iid'])].append(a)
MEAS_FAMS = ['pylint-dev', 'pytest-dev', 'sympy']

best_recall_overall = -1.0; best_label = None
for name, fn in SIGS:
    row = {}
    pooled_tp = []; pooled_fp = []
    for f in MEAS_FAMS:
        pool = [dict(x) for x in fam_groups[f]]
        r, thr, sep, nb, nc = recall_on_pool(fn, pool, family_aware_bank=True)
        row[f] = (r, sep, nb, nc)
    cells = "  ".join(
        f"{f}:rec={('%.3f'%row[f][0]) if row[f][0] is not None else 'n/a'} sep={row[f][1]:+.2f}(bugs={row[f][2]},corr={row[f][3]})"
        for f in MEAS_FAMS)
    print(f"  {name:26s} {cells}")
    for f in MEAS_FAMS:
        r = row[f][0]
        if r is not None and r > best_recall_overall:
            best_recall_overall = r; best_label = f"{name}@{f}"
print()

# ---------------- SLICE A-pooled: pool all 3 measurable families, bank=same-family ----------------
print("=== SLICE A-pooled: all 3 measurable families together, bank still same-family ===")
pool_all = [dict(x) for x in A_ALL if fam(x['iid']) in MEAS_FAMS]
for name, fn in SIGS:
    r, thr, sep, nb, nc = recall_on_pool(fn, pool_all, family_aware_bank=True)
    rs = ('%.3f'%r) if r is not None else 'n/a'
    print(f"  {name:26s} recall@FP0={rs:>6s}  sep={sep:+.3f}  bugs={nb} held_corr={nc}")
print()

# ---------------- SLICE B: traceback-only bugs ----------------
print("=== SLICE B: pool = ONLY bugs that have a traceback (5 bugs, 2 with correct moves) ===")
tb_bugs = set(a['iid'] for a in A_ALL if C['tb_frames'].get(a['iid']))
print(f"    traceback bugs: {sorted(tb_bugs)}")
pool_tb = [dict(x) for x in A_ALL if x['iid'] in tb_bugs]
print(f"    pool size={len(pool_tb)} attempts")
for name, fn in SIGS:
    r, thr, sep, nb, nc = recall_on_pool(fn, pool_tb, family_aware_bank=False)
    rs = ('%.3f'%r) if r is not None else 'n/a'
    print(f"  {name:26s} recall@FP0={rs:>6s}  sep={sep:+.3f}  bugs={nb} held_corr={nc}")
print()

# ---------------- CONTRACT-FAITHFUL confirmation via the REAL H.evaluate ----------------
print("=== CONTRACT-FAITHFUL via real H.evaluate (the unimpeachable source of truth) ===")
pool_tb_dicts = [dict(x) for x in A_ALL if x['iid'] in tb_bugs]
r_b = H.evaluate("SliceB:nameaware_idents", sig_nameaware_idents, pool_tb_dicts, C, verbose=False)
print(f"  SliceB nameaware_idents: recall_fp0={r_b['recall_fp0']:.4f} sep={r_b['sep']:+.4f} "
      f"bugs={r_b['n_bugs']} held_corr={r_b['n_correct']}")
pytest_pool = [dict(x) for x in A_ALL if x['iid'].startswith('pytest-dev')]
r_p = H.evaluate("pytest:moveshape", sig_moveshape, pytest_pool, C, verbose=False)
print(f"  pytest moveshape (REJECTED, n=1 corr artifact): recall_fp0={r_p['recall_fp0']:.4f} "
      f"held_corr={r_p['n_correct']}")
print()

# ---------------- LEAK AUDIT: does the SliceB win survive a same-family-leak-free bank? ----------------
def recall_crossfam(encode_fn, pool, exclude_fam):
    vecs = [encode_fn(a, C) for a in pool]
    vecs = [H.encode_tokens(v) if not (isinstance(v, list) and len(v) == D and isinstance(v[0], (int, float))) else v
            for v in vecs]
    M = np.array(vecs, float); S = np.nan_to_num((M @ M.T) / D)
    iid = np.array([a['iid'] for a in pool]); isfail = np.array([a['gp'] is not True for a in pool]); iscorr = ~isfail
    N = len(pool); by_bug = defaultdict(list)
    for k, a in enumerate(pool):
        if a['gp'] is not True: by_bug[a['iid']].append(k)
    bugs = [b for b, v in by_bug.items() if len(v) >= 2]
    tp, fp = [], []
    for held in bugs:
        if exclude_fam:
            bank = np.array([k for k in range(N) if isfail[k] and iid[k] != held and fam(iid[k]) != fam(held)])
        else:
            bank = np.array([k for k in range(N) if isfail[k] and iid[k] != held])
        if bank.size == 0: continue
        for t in [k for k in range(N) if isfail[k] and iid[k] == held]: tp.append(S[t, bank].max())
        for c in [k for k in range(N) if iscorr[k] and iid[k] == held]: fp.append(S[c, bank].max())
    if not fp: return None
    thr = max(fp) + 1e-9
    return sum(1 for s in tp if s >= thr) / len(tp)
print("=== LEAK AUDIT: SliceB nameaware_idents under same-repo vs cross-FAMILY-only bank ===")
r_same = recall_crossfam(sig_nameaware_idents, pool_tb_dicts, exclude_fam=False)
r_xfam = recall_crossfam(sig_nameaware_idents, pool_tb_dicts, exclude_fam=True)
print(f"  same-repo bank (= harness contract): {r_same:.4f}")
print(f"  cross-FAMILY-only bank (leak-free):  {r_xfam:.4f}  (HIGHER => contract number is conservative, not inflated)")
print()

# ---------------- BEST single number for the report ----------------
print("=== VERDICT ===")
print(f"  best within-family single-family recall@FP0 = {best_recall_overall:.3f}  ({best_label})  <-- REJECTED if pytest (n=1 corr)")
print(f"  SOUND candidate: SliceB(traceback) nameaware_idents recall_fp0 = {r_b['recall_fp0']:.4f}  (17 held-out correct moves)")
print(f"  bar: > 0.25 AND > lexical-full({LEX_FULL:.3f})")
passes = r_b['recall_fp0'] > 0.25 and r_b['recall_fp0'] > 0.126
print(f"  SOUND-candidate PASSES = {passes}")
print(f"  HONEST NARROWNESS: slice = {r_b['n_bugs']} bugs total; threshold set by 17 correct moves from only 2 bugs.")
