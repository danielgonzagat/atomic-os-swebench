#!/usr/bin/env python3
"""Reusable, DETERMINISTIC harness for the structural-trava signature sweep (model-free, by number).

A "signature" is a function encode_fn(attempt, ctx) -> hypervector (list[int], D dims) OR -> set/Counter of
discrete structural tokens (the harness will VSA-encode tokens via typed-role binding). Every number this harness
prints comes from running real code over the 375 real failed/correct SWE-bench repair attempts — never claimed.

THE BAR (the user's falsifiable target): a signature PASSES iff
  recall_fp0 > 0.25  AND  recall_fp0 > lexical_recall_fp0     (beat 1/4 AND beat the trigram baseline, model-free)
where recall_fp0 = leave-one-BUG-out fraction of held-out FAILED moves blocked by a cross-bug trava bank, at the
global threshold where blocking of held-out CORRECT (gate_pass=True) moves is ZERO (the doctrine's sound-trava law).

ctx gives each signature access to the model-free verified world:
  ctx['gold_files'][iid]      -> set of files the GOLD patch edits      (PROVEN causal root; POST-HOC only)
  ctx['gold_syms'][iid]       -> set of (file, enclosing_symbol) gold edits
  ctx['tb_frames'][iid]       -> [(file, func), ...] traceback frames from the issue (APPLY-TIME legal; symptom=last)
  ctx['problem'][iid]         -> problem_statement text
A signature that uses gold_* is POST-HOC (not blockable at apply-time) — flag it; it still bounds what structure
COULD separate. A signature using only the diff + tb_frames + problem is APPLY-TIME legal (a real trava).
"""
import glob, json, re, io, tokenize, hashlib, random, os
from collections import defaultdict, Counter
import pandas as pd
import numpy as np

D = 2048
ROOT = "/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"
PARQUET = ("/Users/danielpenin/.cache/huggingface/hub/datasets--princeton-nlp--SWE-bench_Verified/"
           "snapshots/c104f840cc67f8b6eec6f759ebc8b2693d585d4a/data/test-00000-of-00001.parquet")

# ---------------- VSA primitives ----------------
_AC = {}
def atom(t):
    if t not in _AC:
        h = hashlib.sha256(('A:' + str(t)).encode()).digest(); st = random.getstate()
        random.seed(int.from_bytes(h, 'big')); _AC[t] = [random.choice([1, -1]) for _ in range(D)]
        random.setstate(st)
    return _AC[t]
def bundle(vs):
    if not vs: return [0] * D
    acc = [0] * D
    for v in vs: acc = [a + b for a, b in zip(acc, v)]
    return [1 if x >= 0 else -1 for x in acc]
def sim(a, b): return sum(x * y for x, y in zip(a, b)) / len(a) if a and b else 0.0
def role_bind(role, val):
    r, v = atom('R:' + role), atom('V:' + str(val)); return [x * y for x, y in zip(r, v)]
def encode_tokens(feats):
    """feats: iterable of tokens OR Counter OR dict{token:count} OR iterable of (role,val). -> hypervector."""
    parts = []
    if isinstance(feats, dict):
        items = feats.items()
    else:
        items = [(f, 1) for f in feats]
    for k, c in items:
        if isinstance(k, tuple) and len(k) == 2:
            v = role_bind(k[0], k[1])
        else:
            v = atom('T:' + str(k))
        parts += [v] * min(int(c), 3)
    return bundle(parts)

# ---------------- LEXICAL baseline (char-trigram of raw diff) ----------------
_CC = {}
def _cv(c):
    if c not in _CC:
        h = hashlib.sha256(('C:' + c).encode()).digest(); st = random.getstate()
        random.seed(int.from_bytes(h, 'big')); _CC[c] = np.array([random.choice([1, -1]) for _ in range(D)],
                                                                  dtype=np.float32)
        random.setstate(st)
    return _CC[c]
def lexical_vsa(text):
    """char-trigram random projection, numpy-vectorized across trigrams (same algo as weights_admit, D-dim)."""
    if not text: return [0] * D
    text = "_" + text.lower().strip() + "_"
    if len(text) < 3: return [0] * D
    acc = np.zeros(D, dtype=np.float32)
    for i in range(len(text) - 2):
        v1, v2, v3 = _cv(text[i]), _cv(text[i+1]), _cv(text[i+2])
        v1p = np.roll(v1, -2); v2p = np.roll(v2, -1)
        acc += v1p * v2p * v3
    return np.where(acc >= 0, 1, -1).astype(np.int8).tolist()

# ---------------- diff helpers ----------------
PYKW = set("False None True and as assert async await break class continue def del elif else except finally "
           "for from global if import in is lambda nonlocal not or pass raise return try while with yield".split())
def diff_files(p): return set(re.findall(r'^\+\+\+ b/(.+)$', p or '', re.M))
def abstract_line(line):
    toks = []
    try:
        for tok in tokenize.generate_tokens(io.StringIO(line).readline):
            tt, ts = tok.type, tok.string
            if tt in (tokenize.NL, tokenize.NEWLINE, tokenize.INDENT, tokenize.DEDENT, tokenize.ENCODING,
                      tokenize.ENDMARKER, tokenize.COMMENT): continue
            if tt == tokenize.NAME: toks.append(ts if ts in PYKW else "ID")
            elif tt == tokenize.NUMBER: toks.append("NUM")
            elif tt == tokenize.STRING: toks.append("STR")
            elif tt == tokenize.OP: toks.append(ts)
            elif ts.strip(): toks.append(ts)
    except Exception:
        for w in re.findall(r"[A-Za-z_]\w*|[=!<>+\-*/%]+|[():\[\].,]", line):
            toks.append(w if w in PYKW else ("ID" if re.match(r"[A-Za-z_]", w) else w))
    return tuple(toks)
def diff_added_removed(diff):
    add, rem = [], []
    for l in diff.splitlines():
        if l[:3] in ('+++', '---') or l.startswith('@@') or l.startswith('diff '): continue
        if l.startswith('+') and l[1:].strip(): add.append(l[1:])
        elif l.startswith('-') and l[1:].strip(): rem.append(l[1:])
    return add, rem
def diff_hunk_headers(diff):
    return re.findall(r'@@ -\d+(?:,\d+)? \+\d+(?:,\d+)? @@ ?(.*)', diff)
def tb_frames(text):
    return re.findall(r'File "([^"]+)", line \d+, in (\w+)', text or '')

# ---------------- load data ----------------
def _instance_of(d):
    m = re.search(r'SWE-([\w.-]+__[\w.-]+-\d+)', d.get('task', '')); return m.group(1) if m else None
def load():
    df = pd.read_parquet(PARQUET, columns=["instance_id", "patch", "problem_statement"])
    gold = {r.instance_id: (r.patch, r.problem_statement) for r in df.itertuples()}
    attempts = []
    for f in glob.glob(f'{ROOT}/evidence/**/*.json', recursive=True):
        try: d = json.load(open(f))
        except: continue
        if not isinstance(d, dict): continue
        fd = (d.get('final_diff') or '').strip()
        if not fd: continue
        iid = _instance_of(d)
        if not iid: continue
        attempts.append({'iid': iid, 'fd': fd, 'gp': d.get('gp', d.get('gate_pass'))})
    ctx = {'gold_files': {}, 'gold_syms': {}, 'tb_frames': {}, 'problem': {}}
    for iid, (patch, ps) in gold.items():
        ctx['gold_files'][iid] = set(os.path.basename(x) for x in diff_files(patch))
        ctx['tb_frames'][iid] = [(os.path.basename(fp), fn) for fp, fn in tb_frames(ps)]
        ctx['problem'][iid] = ps or ''
    return attempts, ctx

# ---------------- evaluation (the BAR) ----------------
def evaluate(name, encode_fn, attempts=None, ctx=None, applytime_legal=True, verbose=True):
    """encode_fn(attempt, ctx) -> hypervector (list len D) or token-iterable (encoded via encode_tokens)."""
    if attempts is None: attempts, ctx = load()
    def enc(a):
        r = encode_fn(a, ctx)
        if r and isinstance(r, list) and len(r) == D and isinstance(r[0], (int, float)): return r
        return encode_tokens(r if r is not None else [])
    for a in attempts: a['_v'] = enc(a)
    # vectorize: stack vectors, similarity matrix S = M @ M.T / D
    M = np.array([a['_v'] for a in attempts], dtype=np.float64)
    S = np.nan_to_num((M @ M.T) / D)
    iid = np.array([a['iid'] for a in attempts])
    isfail = np.array([a['gp'] is not True for a in attempts])
    iscorr = ~isfail
    N = len(attempts)
    samebug = iid[:, None] == iid[None, :]
    # confound-free cross-bug separation (upper triangle, cross-bug)
    triu = np.triu(np.ones((N, N), dtype=bool), 1)
    ff_mask = triu & (~samebug) & isfail[:, None] & isfail[None, :]
    fc_mask = triu & (~samebug) & ((isfail[:, None] & iscorr[None, :]) | (iscorr[:, None] & isfail[None, :]))
    ff = float(S[ff_mask].mean()) if ff_mask.any() else 0.0
    fc = float(S[fc_mask].mean()) if fc_mask.any() else 0.0
    # leave-one-bug-out recall@FP0
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
    correct = [a for a in attempts if a['gp'] is True]
    failed = [a for a in attempts if a['gp'] is not True]
    out = {'name': name, 'applytime_legal': applytime_legal, 'sep': ff - fc,
           'xbug_failed_failed': ff, 'xbug_failed_correct': fc,
           'recall_fp0': recall, 'thr': thr, 'n_failed': len(failed), 'n_correct': len(correct),
           'n_bugs': len(bugs)}
    if verbose:
        print(json.dumps(out, indent=2))
    return out

if __name__ == "__main__":
    # baseline self-test: the lexical encoder
    A, C = load()
    print(f"loaded {len(A)} attempts; correct={sum(1 for a in A if a['gp'] is True)}")
    evaluate("LEXICAL-trigram", lambda a, ctx: lexical_vsa(a['fd']), A, C)
