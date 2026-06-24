#!/usr/bin/env python3
"""Sweep of DIVERSE model-free STRUCTURAL signatures vs the lexical baseline, by number (the harness BAR).
Exhausts "a estrutura que já se tem" before any boundary claim. Every number from running real code on 376 real
attempts. A signature returns a token-iterable or (role,val) pairs; the harness VSA-encodes + scores it."""
import re, os
from collections import Counter
import trava_harness as H

A, C = H.load()

def edit_funcs(diff):
    return set(m for h in H.diff_hunk_headers(diff) for m in re.findall(r'(?:def|class)\s+([A-Za-z_]\w*)', h))

# ---- signatures (each: attempt, ctx -> token iterable / (role,val) pairs) ----

def sig_moveshape(a, ctx):
    add, rem = H.diff_added_removed(a['fd']); feats = Counter()
    for role, lines in (('ADD', add), ('DEL', rem)):
        for l in lines:
            ab = H.abstract_line(l)
            for t in ab:
                if t in H.PYKW or not t.isalnum(): feats[f"{role}:U:{t}"] += 1
            for x, y in zip(ab, ab[1:]): feats[f"{role}:B:{x}>{y}"] += 1
    return feats

def sig_keywords(a, ctx):
    add, rem = H.diff_added_removed(a['fd']); feats = Counter()
    for role, lines in (('ADD', add), ('DEL', rem)):
        for l in lines:
            for t in H.abstract_line(l):
                if t in H.PYKW: feats[f"{role}:{t}"] += 1
    return feats

OPS = set("== != <= >= < > = is in not and or += -= += -> :=".split())
def sig_operators(a, ctx):
    add, rem = H.diff_added_removed(a['fd']); feats = Counter()
    for role, lines in (('ADD', add), ('DEL', rem)):
        for l in lines:
            for t in H.abstract_line(l):
                if t in OPS: feats[f"{role}:{t}"] += 1
    return feats

def sig_edit_op_taxonomy(a, ctx):
    """Coarse operation classes (the doctrine's 'operação estrutural'), name-agnostic, rule-based."""
    add, rem = H.diff_added_removed(a['fd']); toks = set()
    addtext = " ".join(add); remtext = " ".join(rem)
    def has(pat, s): return re.search(pat, s) is not None
    if has(r'\bif\b', addtext) and has(r'\breturn\b', addtext): toks.add('ADD_GUARD_RETURN')
    if has(r'\bif\b', addtext) and has(r'\braise\b', addtext): toks.add('ADD_GUARD_RAISE')
    if has(r'\btry\b', addtext) or has(r'\bexcept\b', addtext): toks.add('ADD_TRY')
    if has(r'\bimport\b', addtext): toks.add('ADD_IMPORT')
    if has(r'\breturn\b', addtext) and not has(r'\bif\b', addtext): toks.add('CHANGE_RETURN')
    if has(r'[=!<>]=', addtext) or has(r'\bis\b', addtext): toks.add('CHANGE_COMPARISON')
    if has(r'\bnot\b', addtext): toks.add('ADD_NEGATION')
    if has(r'\bfor\b|\bwhile\b', addtext): toks.add('ADD_LOOP')
    if has(r'\bdef\b', addtext): toks.add('ADD_DEF')
    if has(r'@', addtext): toks.add('ADD_DECORATOR')
    if rem and not add: toks.add('PURE_DELETE')
    if add and not rem: toks.add('PURE_ADD')
    # magnitude bucket
    toks.add(f'NADD_{min(len(add),5)}'); toks.add(f'NDEL_{min(len(rem),5)}')
    return toks

def sig_change_polarity(a, ctx):
    add, rem = H.diff_added_removed(a['fd'])
    nh = len(H.diff_hunk_headers(a['fd']))
    return {f'NADD_{min(len(add),8)}', f'NDEL_{min(len(rem),8)}', f'NHUNK_{min(nh,5)}',
            'NET_ADD' if len(add) > len(rem) else 'NET_DEL' if len(rem) > len(add) else 'NET_BAL'}

def sig_nodetype_hist(a, ctx):
    """Python-ast node-type histogram of the added lines (the 'purer AST' rung from weights_autoclass docstring)."""
    import ast
    add, rem = H.diff_added_removed(a['fd']); feats = Counter()
    for role, lines in (('ADD', add), ('DEL', rem)):
        src = "\n".join(re.sub(r'^\s+', '', l) for l in lines)  # dedent-ish
        for snippet in (src, "if True:\n " + src.replace("\n", "\n ")):
            try:
                tree = ast.parse(snippet)
                for node in ast.walk(tree):
                    feats[f'{role}:{type(node).__name__}'] += 1
                break
            except Exception:
                continue
    return feats

def sig_tb_relation(a, ctx):
    """Apply-time-legal: edit-target vs TRACEBACK frames (symptom=last frame, upstream=others). The user's literal
    predicate computed from the traceback alone (no gold). Sparse: only ~55/372 attempts have a traceback."""
    frames = ctx['tb_frames'].get(a['iid'], [])
    ef = edit_funcs(a['fd']); efiles = set(os.path.basename(x) for x in H.diff_files(a['fd']))
    toks = set()
    if not frames:
        toks.add('NO_TRACEBACK'); return toks
    tb_funcs = set(fn for _, fn in frames); tb_files = set(fp for fp, _ in frames)
    symptom = frames[-1][1]; upstream = tb_funcs - {symptom}
    toks.add('HAS_TRACEBACK')
    toks.add('EDIT_FILE_IN_TB' if (efiles & tb_files) else 'EDIT_FILE_NOT_IN_TB')
    if ef & {symptom}: toks.add('EDIT_AT_SYMPTOM')
    if ef & upstream: toks.add('EDIT_AT_UPSTREAM')
    if ef and not (ef & tb_funcs): toks.add('EDIT_FUNC_OUTSIDE_TB')
    return toks

def sig_indent_shape(a, ctx):
    """Control-flow nesting shape of the change: did it add an indentation level (wrap in block), etc."""
    add, rem = H.diff_added_removed(a['fd'])
    def ind(l): return len(l) - len(l.lstrip())
    toks = set()
    if add: toks.add(f'ADD_MAXIND_{min(max(ind(l) for l in add)//4,6)}')
    if rem: toks.add(f'DEL_MAXIND_{min(max(ind(l) for l in rem)//4,6)}')
    aset = set(ind(l) for l in add); rset = set(ind(l) for l in rem)
    if aset - rset: toks.add('ADDED_NESTING')
    return toks

def sig_combined(a, ctx):
    """Fusion of the strongest discrete cues: taxonomy + keywords + operators + tb-relation."""
    out = set()
    out |= set(sig_edit_op_taxonomy(a, ctx))
    for k in sig_keywords(a, ctx): out.add('K:' + k)
    for k in sig_operators(a, ctx): out.add('O:' + k)
    out |= set('TB:' + t for t in sig_tb_relation(a, ctx))
    return out

# ---- POST-HOC ceiling: uses GOLD (not a real trava, bounds what structure COULD separate) ----
def sig_edit_vs_gold(a, ctx):
    gold = ctx['gold_files'].get(a['iid'], set())
    efiles = set(os.path.basename(x) for x in H.diff_files(a['fd']))
    toks = set()
    toks.add('EDIT_HITS_GOLD_FILE' if (efiles & gold) else 'EDIT_MISSES_GOLD_FILE')
    toks.add(f'NEXTRA_{min(len(efiles - gold),4)}')   # files edited beyond gold
    toks.add(f'NMISS_{min(len(gold - efiles),4)}')     # gold files not touched
    return toks

SIGS = [
    ('LEXICAL-trigram(baseline)', lambda a, ctx: H.lexical_vsa(a['fd']), True),
    ('moveshape', sig_moveshape, True),
    ('keywords', sig_keywords, True),
    ('operators', sig_operators, True),
    ('edit_op_taxonomy', sig_edit_op_taxonomy, True),
    ('change_polarity', sig_change_polarity, True),
    ('ast_nodetype_hist', sig_nodetype_hist, True),
    ('tb_relation(applytime)', sig_tb_relation, True),
    ('indent_shape', sig_indent_shape, True),
    ('combined', sig_combined, True),
    ('edit_vs_gold(POSTHOC-ceiling)', sig_edit_vs_gold, False),
]

def _run():
  print(f"{'signature':34s} {'applytime':9s} {'recall@FP0':>11s} {'sep':>8s}  {'ff':>6s} {'fc':>6s}  verdict")
  print("-" * 92)
  lex_recall = None
  results = []
  for name, fn, legal in SIGS:
    r = H.evaluate(name, fn, [dict(x) for x in A], C, applytime_legal=legal, verbose=False)
    results.append(r)
    if name.startswith('LEXICAL'): lex_recall = r['recall_fp0']
    rec = r['recall_fp0']
    passes = (rec is not None and rec > 0.25 and (lex_recall is None or rec > lex_recall))
    print(f"{name:34s} {str(legal):9s} {('%.3f'%rec) if rec is not None else '  n/a':>11s} "
          f"{r['sep']:+.3f} {r['xbug_failed_failed']:6.3f} {r['xbug_failed_correct']:6.3f}  "
          f"{'*** PASS' if passes else 'fail'}")
  print("-" * 92)
  npass = sum(1 for r in results if r['recall_fp0'] and r['recall_fp0'] > 0.25 and r['recall_fp0'] > lex_recall)
  print(f"BAR: recall@FP0 > 0.25 AND > lexical({lex_recall:.3f}), model-free.  PASSES: {npass}")


if __name__ == "__main__":
    _run()
