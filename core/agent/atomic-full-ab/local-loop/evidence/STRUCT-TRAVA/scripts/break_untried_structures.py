#!/usr/bin/env python3
"""ATTACK on the null: model-free structural signatures NOT tried in sweep.py.
Every number from H.evaluate (real, leak-free, deterministic). No model, no LLM, no per-class concept map.

Untried axes attacked here:
  U1  char-class TRANSITION texture of the diff (sub-token byte-class bigrams) -- never tried (token-level only before)
  U2  abstract-line ordered n-gram SEQUENCE (3,4-grams of name-agnostic tokens) -- moveshape was only uni+bi BAG
  U3  added-vs-removed CONTRAST shape (what kind of line replaced what kind) -- relational, never tried
  U4  identifier-REUSE topology: did the added code introduce NEW identifiers vs reuse removed ones (name-agnostic
      via positional aliasing) -- captures 'hallucinated symbol' wrongness, never tried
  U5  problem<->edit token-role binding (apply-time legal: bind problem-keyword presence to edit-op) -- relational
  U6  diff DENSITY / hunk-dispersion geometry (how spread out the edit is across the file) -- never tried
  U7  FUSION of the above
"""
import re, io, tokenize
from collections import Counter, defaultdict
import trava_harness as H

A, C = H.load()

# ---------- U1: char-class transition texture ----------
def _cc(ch):
    if ch.isalpha(): return 'a'
    if ch.isdigit(): return 'd'
    if ch.isspace(): return 's'
    return ch  # punctuation kept literal (operators matter)
def sig_charclass_trans(a, ctx):
    add, rem = H.diff_added_removed(a['fd']); feats = Counter()
    for role, lines in (('ADD', add), ('DEL', rem)):
        for l in lines:
            cl = [_cc(c) for c in l]
            for x, y in zip(cl, cl[1:]):
                feats[f'{role}:{x}{y}'] += 1
    return feats

# ---------- U2: abstract-line ordered n-grams ----------
def sig_abstract_ngrams(a, ctx):
    add, rem = H.diff_added_removed(a['fd']); feats = Counter()
    for role, lines in (('ADD', add), ('DEL', rem)):
        for l in lines:
            ab = H.abstract_line(l)
            for n in (3, 4):
                for i in range(len(ab) - n + 1):
                    feats[f'{role}:{n}:' + '>'.join(ab[i:i+n])] += 1
    return feats

# ---------- U3: added-vs-removed contrast shape ----------
def _line_kind(line):
    ab = H.abstract_line(line)
    if not ab: return 'EMPTY'
    head = ab[0]
    if head in ('if','elif','else','for','while','try','except','finally','with'): return 'CTRL:'+head
    if head in ('return','raise','yield','assert','pass','break','continue'): return 'STMT:'+head
    if head in ('def','class'): return 'DECL:'+head
    if head in ('import','from'): return 'IMPORT'
    if '=' in ab and not any(o in ab for o in ('==','!=','<=','>=')): return 'ASSIGN'
    if '(' in ab: return 'CALL'
    return 'EXPR'
def sig_contrast_shape(a, ctx):
    add, rem = H.diff_added_removed(a['fd'])
    ak = [_line_kind(l) for l in add]; rk = [_line_kind(l) for l in rem]
    feats = Counter()
    for k in ak: feats['A:'+k] += 1
    for k in rk: feats['D:'+k] += 1
    # paired contrast: aligned by position (replacement intent)
    for i in range(min(len(ak), len(rk))):
        feats[f'SWAP:{rk[i]}=>{ak[i]}'] += 1
    return feats

# ---------- U4: identifier-reuse topology (name-agnostic) ----------
def _idents(line):
    out = []
    try:
        for tok in tokenize.generate_tokens(io.StringIO(line).readline):
            if tok.type == tokenize.NAME and tok.string not in H.PYKW:
                out.append(tok.string)
    except Exception:
        out = [w for w in re.findall(r'[A-Za-z_]\w*', line) if w not in H.PYKW]
    return out
def sig_ident_reuse(a, ctx):
    add, rem = H.diff_added_removed(a['fd'])
    add_ids = Counter(i for l in add for i in _idents(l))
    rem_ids = Counter(i for l in rem for i in _idents(l))
    feats = Counter()
    introduced = set(add_ids) - set(rem_ids)   # NEW symbols the edit conjures
    dropped = set(rem_ids) - set(add_ids)
    kept = set(add_ids) & set(rem_ids)
    feats[f'NEW_{min(len(introduced),6)}'] += 1
    feats[f'DROP_{min(len(dropped),6)}'] += 1
    feats[f'KEPT_{min(len(kept),6)}'] += 1
    tot = len(introduced) + len(kept) + 1
    feats[f'NEWRATE_{round(len(introduced)/tot,1)}'] += 1
    return feats

# ---------- U5: problem<->edit relational binding (apply-time legal) ----------
_STOP = set('the a an of to in is be on for and or not this that with as by from at it if def class self return'.split())
def sig_problem_edit_bind(a, ctx):
    ps = (ctx['problem'].get(a['iid'], '') or '').lower()
    pwords = set(w for w in re.findall(r'[a-z_]{3,}', ps) if w not in _STOP)
    add, rem = H.diff_added_removed(a['fd'])
    add_ids = set(i.lower() for l in add for i in _idents(l))
    # which edit identifiers are 'on-topic' (named in the issue) vs off-topic
    on = add_ids & pwords; off = add_ids - pwords
    feats = Counter()
    tot = len(add_ids) + 1
    feats[f'ONTOPIC_{round(len(on)/tot,1)}'] += 1
    feats[f'NON_{min(len(off),6)}'] += 1
    # does the edit mention an error/exception class that the problem mentions?
    add_text = ' '.join(add).lower()
    for kw in ('error','exception','none','empty','raise','default','missing','attribute','type','value','key','index'):
        if kw in ps and kw in add_text: feats['BOTH:'+kw] += 1
    return feats

# ---------- U6: hunk-dispersion geometry ----------
def sig_hunk_geometry(a, ctx):
    diff = a['fd']
    hunks = re.findall(r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@', diff)
    nf = len(H.diff_files(diff))
    feats = Counter()
    feats[f'NHUNK_{min(len(hunks),8)}'] += 1
    feats[f'NFILE_{min(nf,4)}'] += 1
    starts = sorted(int(h[0]) for h in hunks if h[0])
    if len(starts) >= 2:
        span = starts[-1] - starts[0]
        feats[f'SPAN_{min(span//50,8)}'] += 1   # how spread the edits are (file line span / 50)
        feats[f'MULTIHUNK'] += 1
    elif len(starts) == 1:
        feats['SINGLEHUNK'] += 1
    return feats

# ---------- U7: fusion ----------
def sig_fusion(a, ctx):
    out = Counter()
    for k, v in sig_charclass_trans(a, ctx).items(): out['cc:'+k] += v
    for k, v in sig_abstract_ngrams(a, ctx).items(): out['ng:'+k] += v
    for k, v in sig_contrast_shape(a, ctx).items(): out['ct:'+k] += v
    for k, v in sig_ident_reuse(a, ctx).items(): out['ir:'+k] += v
    for k, v in sig_problem_edit_bind(a, ctx).items(): out['pe:'+k] += v
    return out

SIGS = [
    ('LEXICAL(baseline)', lambda a, ctx: H.lexical_vsa(a['fd']), True),
    ('U1_charclass_trans', sig_charclass_trans, True),
    ('U2_abstract_ngrams', sig_abstract_ngrams, True),
    ('U3_contrast_shape', sig_contrast_shape, True),
    ('U4_ident_reuse', sig_ident_reuse, True),
    ('U5_problem_edit_bind', sig_problem_edit_bind, True),
    ('U6_hunk_geometry', sig_hunk_geometry, True),
    ('U7_fusion', sig_fusion, True),
]

print(f"{'signature':24s} {'recall@FP0':>11s} {'sep':>8s} {'ff':>6s} {'fc':>6s}  verdict")
print('-' * 70)
lex = None
for name, fn, legal in SIGS:
    r = H.evaluate(name, fn, [dict(x) for x in A], C, applytime_legal=legal, verbose=False)
    if name.startswith('LEXICAL'): lex = r['recall_fp0']
    rec = r['recall_fp0']
    passes = rec is not None and rec > 0.25 and (lex is None or rec > lex)
    print(f"{name:24s} {('%.3f'%rec) if rec is not None else 'n/a':>11s} "
          f"{r['sep']:+.3f} {r['xbug_failed_failed']:6.3f} {r['xbug_failed_correct']:6.3f}  "
          f"{'*** PASS' if passes else 'fail'}")
print('-' * 70)
print(f"BAR: recall_fp0 > 0.25 AND > lexical({lex:.3f}), model-free.")
