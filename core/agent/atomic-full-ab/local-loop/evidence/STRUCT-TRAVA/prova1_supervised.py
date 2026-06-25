#!/usr/bin/env python3
"""PROVA 1 — does a SUPERVISED net (trained on atomic's OWN execution labels) SEPARATE
correct from failed repair moves HELD-OUT, breaking the model-free wall (recall@FP0 > 0.25)?

This is the genuinely-unmeasured question. Prior evidence brackets it but does not resolve it:
  - UNSUPERVISED max-cosine to a failed-bank (the harness `recall_fp0`): ~0 official / 0.126 lexical (the WALL).
  - A label-LEAKING (in-sample) least-squares ceiling on def-use tokens: ~0.85 (an upper bound, NOT held-out).
The open question: a real supervised classifier, leave-one-BUG-out, at FP0 — does it generalize > 0.25?

DESIGN (faithful to the wall's geometry, no leakage):
  data    : OFFICIAL labels only (score_*.log resolved-flag ↔ pred_*.jsonl model_patch, byte-exact join).
            166 moves / 12 bugs / 7 bugs with both classes.  y=1 == FAILED (the class the trava must fire on).
  features: MODEL-FREE, apply-time legal, from the DIFF text only (no gold_*, no model, no embedding):
            char-trigram (lexical) + name-agnostic def-use role tokens + name-agnostic AST node ins/del bag.
            Hashed into D dims, per-family selectable for ablation.
  net     : numpy logistic regression (L2). The doctrine's small CPU tool-net; SOFT (the byte-law is the hard guard).
  metric  : leave-one-BUG-out.  thr = max P(fail) over ALL held-out CORRECT moves (+eps) => 0 correct blocked (FP0).
            recall@FP0 = frac of held-out FAILED moves with P(fail) >= thr.  Also recall at FP budget {1,2,3,5}.
  controls: (a) in-sample recall@FP0 (reproduce the ~0.85 ceiling => signal exists);
            (b) PERMUTED labels (shuffle y in training fold) => held-out recall@FP0 MUST collapse (no leakage);
            (c) learning curve: held-out recall@FP0 vs #training bugs;
            (d) feature ablation: lexical / defuse / ast / fused.
  bar     : held-out recall@FP0 > 0.25 (beat the 1/4 wall) AND > the lexical control, with a RISING curve and a
            FLAT permuted control. Anything else is an honest NULL for the supervised escape.
"""
import glob, re, os, json, ast, io, hashlib
from collections import defaultdict, Counter
import numpy as np

np.random.seed(1234)
ROOT = "/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"
D = 4096

# ============================================================ data: official labels
def norm(s): return (s or '').strip()
def build_official():
    off = {}
    for s in glob.glob(f'{ROOT}/evidence/**/score_*.log', recursive=True):
        txt = open(s, errors='ignore').read()
        m = re.search(r'Instances resolved:\s*(\d+)', txt)
        sub = re.search(r'Instances submitted:\s*(\d+)', txt)
        if not m: continue
        if sub and int(sub.group(1)) != 1: continue
        resolved = int(m.group(1)) >= 1
        stem = os.path.basename(s)[len('score_'):-len('.log')]
        pred = os.path.join(os.path.dirname(s), f'pred_{stem}.jsonl')
        if not os.path.exists(pred): continue
        try: rows = [json.loads(l) for l in open(pred) if l.strip()]
        except Exception: continue
        if not rows: continue
        r = rows[0]; iid = r.get('instance_id'); patch = norm(r.get('model_patch'))
        if not iid or not patch: continue
        key = (iid, patch)
        off[key] = off.get(key, False) or resolved   # resolved-wins on duplicate
    moves = [{'iid': iid, 'fd': patch, 'fail': (not res)} for (iid, patch), res in off.items()]
    return moves

# ============================================================ features (model-free, diff-only)
def diff_added_removed(diff):
    add, rem = [], []
    for l in diff.splitlines():
        if l[:3] in ('+++', '---') or l.startswith('@@') or l.startswith('diff '): continue
        if l.startswith('+') and l[1:].strip(): add.append(l[1:])
        elif l.startswith('-') and l[1:].strip(): rem.append(l[1:])
    return add, rem
def diff_ctx(diff):
    out = []
    for l in diff.splitlines():
        if l[:3] in ('+++', '---') or l.startswith('@@') or l.startswith('diff '): continue
        if l.startswith(' '): out.append(l[1:])
    return out

# --- def-use (name-agnostic) ---
def _try_parse(line):
    s2 = line.rstrip().lstrip()
    if not s2: return None
    for cand in (s2, (s2 + "\n    pass") if s2.endswith(":") else None, "_ = " + s2):
        if cand is None: continue
        try: return ast.parse(cand)
        except Exception: continue
    return None
def _defs_uses(tree):
    defs, uses, roles = set(), set(), Counter()
    if tree is None: return defs, uses, roles
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            roles['DEF_ASSIGN'] += 1
            for tgt in node.targets:
                for n in ast.walk(tgt):
                    if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Store): defs.add(n.id)
                    if isinstance(n, ast.Attribute) and isinstance(n.ctx, ast.Store): roles['DEF_ATTR'] += 1
                    if isinstance(n, ast.Subscript) and isinstance(n.ctx, ast.Store): roles['DEF_SUBSCR'] += 1
        elif isinstance(node, ast.AugAssign):
            roles['DEF_AUGASSIGN'] += 1
            for n in ast.walk(node.target):
                if isinstance(n, ast.Name): defs.add(n.id)
        elif isinstance(node, ast.AnnAssign):
            roles['DEF_ANNASSIGN'] += 1
            if isinstance(node.target, ast.Name): defs.add(node.target.id)
        elif isinstance(node, ast.NamedExpr):
            roles['DEF_WALRUS'] += 1
            if isinstance(node.target, ast.Name): defs.add(node.target.id)
        elif isinstance(node, ast.For):
            roles['DEF_FORTARGET'] += 1
            for n in ast.walk(node.target):
                if isinstance(n, ast.Name): defs.add(n.id)
        elif isinstance(node, ast.comprehension):
            roles['DEF_COMP'] += 1
            for n in ast.walk(node.target):
                if isinstance(n, ast.Name): defs.add(n.id)
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            roles['DEF_FUNC'] += 1
            for arg in node.args.args + node.args.kwonlyargs: defs.add(arg.arg)
        if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load): uses.add(node.id)
        if isinstance(node, ast.Attribute) and isinstance(node.ctx, ast.Load): roles['USE_ATTR'] += 1
        if isinstance(node, ast.Subscript) and isinstance(node.ctx, ast.Load): roles['USE_SUBSCR'] += 1
        if isinstance(node, ast.Call):
            roles['USE_CALL'] += 1
            if node.keywords: roles['USE_KWARG'] += 1
        if isinstance(node, ast.Compare):
            roles['USE_COMPARE'] += 1
            for cmp in node.comparators + [node.left]:
                if isinstance(cmp, ast.Constant) and cmp.value is None: roles['CMP_NONE'] += 1
        if isinstance(node, ast.BoolOp): roles['USE_BOOLOP'] += 1
        if isinstance(node, ast.IfExp): roles['USE_TERNARY'] += 1
        if isinstance(node, ast.Return): roles['HAS_RETURN'] += 1
    return defs, uses, roles
def feats_defuse(fd):
    add, rem = diff_added_removed(fd); ctxl = diff_ctx(fd)
    feats = Counter()
    add_defs = add_uses = None
    A_def, A_use, C_def, R_use, R_def = set(), set(), set(), set(), set()
    for role, lines in (('ADD', add), ('DEL', rem)):
        for l in lines:
            d, u, r = _defs_uses(_try_parse(l))
            for k, c in r.items(): feats[f'{role}:{k}'] += c
            if d: feats[f'{role}:NDEF_{min(len(d),3)}'] += 1
            if u: feats[f'{role}:NUSE_{min(len(u),3)}'] += 1
            if role == 'ADD': A_def |= d; A_use |= u
            else: R_def |= d; R_use |= u
    for l in ctxl:
        d, _, _ = _defs_uses(_try_parse(l)); C_def |= d
    if A_use & C_def: feats[f'ADD_USE_OF_CTXDEF_{min(len(A_use&C_def),3)}'] += 1
    if A_use & A_def: feats[f'ADD_USE_OF_ADDDEF_{min(len(A_use&A_def),3)}'] += 1
    if A_def & (R_use | R_def): feats[f'ADD_REDEF_{min(len(A_def&(R_use|R_def)),3)}'] += 1
    if A_def - A_use: feats[f'ADD_DEF_ESCAPE_{min(len(A_def-A_use),3)}'] += 1
    if A_use and not A_def: feats['ADD_PURE_USE'] += 1
    if A_def and not A_use: feats['ADD_PURE_DEF'] += 1
    return {f'du::{k}': v for k, v in feats.items()}

# --- AST node-type ins/del bag (name-agnostic) ---
def _node_types(src):
    try: tree = ast.parse(src)
    except Exception:
        try: tree = ast.parse("_ = " + src.strip())
        except Exception: return Counter()
    return Counter(type(n).__name__ for n in ast.walk(tree))
def feats_ast(fd):
    add, rem = diff_added_removed(fd)
    na = _node_types("\n".join(s.lstrip() for s in add))
    nb = _node_types("\n".join(s.lstrip() for s in rem))
    feats = Counter()
    for k in set(na) | set(nb):
        d = na[k] - nb[k]
        if d > 0: feats[f'INS_{k}'] += min(d, 3)
        elif d < 0: feats[f'DEL_{k}'] += min(-d, 3)
    return {f'ast::{k}': v for k, v in feats.items()}

# --- char-trigram lexical ---
def feats_lex(fd):
    t = "_" + (fd or '').lower().strip() + "_"
    c = Counter()
    for i in range(len(t) - 2): c['lex::' + t[i:i+3]] += 1
    return c

def _hash(tok): return int.from_bytes(hashlib.sha256(tok.encode()).digest()[:4], 'big') % D
_FEAT_CACHE = {}   # id(moves) -> {'lex':Counter, 'du':Counter, 'ast':Counter} per move
def _move_feats(moves):
    key = id(moves)
    if key not in _FEAT_CACHE:
        per = []
        for m in moves:
            per.append({'lex': feats_lex(m['fd']), 'du': feats_defuse(m['fd']), 'ast': feats_ast(m['fd'])})
        _FEAT_CACHE[key] = per
    return _FEAT_CACHE[key]
_VEC_CACHE = {}    # (id(moves), frozenset(families)) -> X
def vectorize(moves, families):
    ck = (id(moves), frozenset(families))
    if ck in _VEC_CACHE: return _VEC_CACHE[ck]
    per = _move_feats(moves)
    X = np.zeros((len(moves), D), dtype=np.float64)
    for i, fams in enumerate(per):
        feats = Counter()
        for fam in families: feats.update(fams[fam])
        for tok, c in feats.items():
            X[i, _hash(tok)] += min(c, 3)
    _VEC_CACHE[ck] = X
    return X

# ============================================================ numpy logistic regression (L2)
def fit_logreg(X, y, l2=1.0, iters=400, lr=0.5):
    n, d = X.shape
    mu = X.mean(0); sd = X.std(0) + 1e-9
    Xs = (X - mu) / sd
    w = np.zeros(d); b = 0.0
    for _ in range(iters):
        z = Xs @ w + b
        p = 1.0 / (1.0 + np.exp(-np.clip(z, -30, 30)))
        g = p - y
        gw = Xs.T @ g / n + l2 * w / n
        gb = g.mean()
        w -= lr * gw; b -= lr * gb
    return (w, b, mu, sd)
def predict(model, X):
    w, b, mu, sd = model
    z = ((X - mu) / sd) @ w + b
    return 1.0 / (1.0 + np.exp(-np.clip(z, -30, 30)))

# ============================================================ FP0 metric (the wall's geometry)
def recall_at_fp(scores, y, group, fp_budget=0):
    """scores=P(fail); y=1 failed; recall of held-out FAILED at threshold allowing fp_budget held-out CORRECT blocked."""
    corr = scores[y == 0]; fail = scores[y == 1]
    if len(corr) == 0 or len(fail) == 0: return None
    corr_sorted = np.sort(corr)[::-1]
    # allow fp_budget correct moves to be blocked: threshold just above the (fp_budget+1)-th highest correct
    idx = min(fp_budget, len(corr_sorted) - 1)
    thr = corr_sorted[idx] + 1e-12 if fp_budget == 0 else corr_sorted[idx] + 1e-12
    # FP0: thr above the max correct. FP=k: thr above the (k+1)th-highest correct (so k correct blocked).
    if fp_budget == 0:
        thr = corr_sorted[0] + 1e-12
    else:
        thr = corr_sorted[min(fp_budget, len(corr_sorted)-1)] + 1e-12
    return float((fail >= thr).mean())

def loo_bug_scores(moves, families, permute=False, train_bug_cap=None, seed=0):
    """Leave-one-BUG-out. Returns pooled held-out (scores, y) over folds that have >=1 held correct AND we can train."""
    rng = np.random.default_rng(seed)
    X = vectorize(moves, families)
    y = np.array([1.0 if m['fail'] else 0.0 for m in moves])
    g = np.array([m['iid'] for m in moves])
    bugs = sorted(set(g))
    pooled_s, pooled_y = [], []
    for held in bugs:
        te = (g == held)
        tr = ~te
        bugs_tr = [b for b in bugs if b != held]
        if train_bug_cap is not None and len(bugs_tr) > train_bug_cap:
            keep = set(rng.choice(bugs_tr, size=train_bug_cap, replace=False))
            tr = tr & np.array([b in keep for b in g])
        ytr = y[tr].copy()
        if permute: rng.shuffle(ytr)
        if ytr.sum() == 0 or (1 - ytr).sum() == 0:  # need both classes to train
            continue
        model = fit_logreg(X[tr], ytr)
        s = predict(model, X[te])
        pooled_s.append(s); pooled_y.append(y[te])
    if not pooled_s: return None, None
    return np.concatenate(pooled_s), np.concatenate(pooled_y)

def insample_scores(moves, families):
    X = vectorize(moves, families)
    y = np.array([1.0 if m['fail'] else 0.0 for m in moves])
    model = fit_logreg(X, y)
    return predict(model, X), y

# ============================================================ run
if __name__ == "__main__":
    moves = build_official()
    nC = sum(1 for m in moves if not m['fail']); nF = sum(1 for m in moves if m['fail'])
    nb = len(set(m['iid'] for m in moves))
    print(f"OFFICIAL corpus: {len(moves)} moves  correct={nC} failed={nF}  bugs={nb}")
    print(f"BAR: held-out recall@FP0 > 0.25 AND > lexical control; rising curve; FLAT permuted.\n")

    print("=== (1) IN-SAMPLE ceiling (train==test) — does the signal EXIST? ===")
    for fam in (('lex',), ('du',), ('ast',), ('lex','du','ast')):
        s, y = insample_scores(moves, set(fam))
        r0 = recall_at_fp(s, y, None, 0)
        print(f"  fused={'+'.join(fam):14s} in-sample recall@FP0 = {r0:.4f}")

    print("\n=== (2) HELD-OUT leave-one-BUG-out recall@FP0 (THE number) ===")
    for fam in (('lex',), ('du',), ('ast',), ('lex','du','ast')):
        s, y = loo_bug_scores(moves, set(fam))
        if s is None: print(f"  {'+'.join(fam):14s} n/a"); continue
        row = " ".join(f"FP{b}={(recall_at_fp(s,y,None,b) or 0.0):.3f}" for b in (0,1,2,3,5))
        verdict = "*** PASS" if (recall_at_fp(s,y,None,0) or 0.0) > 0.25 else "fail"
        print(f"  {'+'.join(fam):14s} {row}   {verdict}")

    print("\n=== (3) PERMUTED-label control (held-out; MUST be ~0 / flat) ===")
    for seed in (0,1,2):
        s, y = loo_bug_scores(moves, {'lex','du','ast'}, permute=True, seed=seed)
        print(f"  seed={seed} fused permuted held-out recall@FP0 = {recall_at_fp(s,y,None,0):.4f}  (FP3={recall_at_fp(s,y,None,3):.4f})")

    print("\n=== (4) LEARNING CURVE — held-out recall@FP0 vs #training bugs (fused) ===")
    for cap in (1,2,3,4,6,8,11):
        rs = []
        for seed in range(4):
            s, y = loo_bug_scores(moves, {'lex','du','ast'}, train_bug_cap=cap, seed=seed)
            if s is not None: rs.append(recall_at_fp(s,y,None,0))
        if rs: print(f"  train_bugs<= {cap:2d}: held-out recall@FP0 = {np.mean(rs):.4f}  (±{np.std(rs):.3f}, n={len(rs)})")
