#!/usr/bin/env python3
"""ANGLE: ast_tree_edit  (model-free, deterministic).

Idea: for each diff hunk, reconstruct the BEFORE fragment (removed lines) and the AFTER fragment
(added lines), parse each to a Python AST, and compute the AST EDIT OPERATION = the multiset of node
types inserted / deleted / (relabeled). Cluster attempts by this name-agnostic tree-edit signature.

Two encodings reported:
  (1) node-type INSERT/DELETE multiset per hunk (cheap Zhang-Shasha-ish edit on node-type bags)
  (2) the same but with shallow STRUCTURAL CONTEXT (parent->child node-type edges of the changed region)

Everything name-agnostic: identifiers, literals collapse to their ast node TYPE only (ast.walk gives types,
not names, so this is intrinsic). Every number comes from H.evaluate (the real leave-one-bug-out BAR).
"""
import re, ast, io, tokenize, textwrap
from collections import Counter
import trava_harness as H

A, C = H.load()

# ---------------- hunk reconstruction ----------------
def parse_hunks(diff):
    """Return list of hunks; each hunk = (before_lines, after_lines) with leading +/- stripped.
    Context (unchanged) lines go into BOTH before and after so fragments are more parseable."""
    hunks = []
    cur_b, cur_a, inhunk = [], [], False
    for l in (diff or '').splitlines():
        if l.startswith('@@'):
            if inhunk and (cur_b or cur_a):
                hunks.append((cur_b, cur_a))
            cur_b, cur_a, inhunk = [], [], True
            continue
        if not inhunk:
            continue
        if l[:3] in ('+++', '---') or l.startswith('diff '):
            continue
        if l.startswith('+'):
            cur_a.append(l[1:])
        elif l.startswith('-'):
            cur_b.append(l[1:])
        else:  # context line (starts with ' ' or empty)
            ctx = l[1:] if l.startswith(' ') else l
            cur_b.append(ctx)
            cur_a.append(ctx)
    if inhunk and (cur_b or cur_a):
        hunks.append((cur_b, cur_a))
    return hunks

def try_parse(lines):
    """Robustly parse a list of source lines to an AST. Returns ast.Module or None.
    Tries: raw, dedented, dedented-wrapped-in-if, dedented-wrapped-in-def, line-by-line expr fallback."""
    if not lines:
        return None
    raw = "\n".join(lines)
    ded = textwrap.dedent(raw)
    candidates = [ded, raw]
    # wrap in a block (handles fragments that are bodies of if/for/def, or that start indented)
    body = textwrap.indent(ded, "    ")
    candidates.append("if True:\n" + body)
    candidates.append("def _f():\n" + body)
    candidates.append("class _C:\n" + body)
    for src in candidates:
        try:
            return ast.parse(src)
        except Exception:
            continue
    # last resort: parse each line independently, union the partial trees
    parsed_any = False
    mod = ast.Module(body=[], type_ignores=[])
    for ln in lines:
        s = ln.strip()
        if not s:
            continue
        for cand in (s, "if True:\n    " + s, "def _f():\n    " + s):
            try:
                t = ast.parse(cand)
                mod.body.extend(t.body)
                parsed_any = True
                break
            except Exception:
                continue
    return mod if parsed_any else None

# name-agnostic node bag: ast.walk gives node TYPES; we never read .id/.attr/.s/.n so it's intrinsic.
# We DO keep operator subtypes (Add/Sub/Lt/Eq/...) and ctx is dropped (Load/Store/Del are noise).
NOISE = {'Load', 'Store', 'Del', 'Module', 'Expr', 'arguments', 'arg'}
def node_bag(tree):
    c = Counter()
    if tree is None:
        return c
    for n in ast.walk(tree):
        tn = type(n).__name__
        if tn in NOISE:
            continue
        c[tn] += 1
    return c

def edge_bag(tree):
    """parent_type -> child_type edges of the changed region (shallow structural context)."""
    c = Counter()
    if tree is None:
        return c
    for n in ast.walk(tree):
        pt = type(n).__name__
        if pt in NOISE:
            continue
        for ch in ast.iter_child_nodes(n):
            ct = type(ch).__name__
            if ct in NOISE:
                continue
            c[f'{pt}>{ct}'] += 1
    return c

# ---------------- signatures ----------------
def sig_tree_edit(a, ctx):
    """The AST edit operation: per hunk, INS/DEL multiset of node types (before -> after).
    Token = ('INS'|'DEL', node_type). Aggregated across hunks of the attempt."""
    feats = Counter()
    saw_parse = False
    for before, after in parse_hunks(a['fd']):
        tb, ta = try_parse(before), try_parse(after)
        nb, na = node_bag(tb), node_bag(ta)
        if tb is not None or ta is not None:
            saw_parse = True
        # multiset difference = the tree edit
        ins = na - nb   # node types present-more in AFTER (inserted)
        dele = nb - na  # node types present-more in BEFORE (deleted)
        for t, cnt in ins.items():
            feats[('INS', t)] += cnt
        for t, cnt in dele.items():
            feats[('DEL', t)] += cnt
    if not feats:
        feats[('NOEDIT', 'X')] = 1 if not saw_parse else 0
        feats[('PARSED_NOEDIT', 'X')] = 1 if saw_parse else 0
    return feats

def sig_tree_edit_edges(a, ctx):
    """AST edit on parent->child EDGES (structural context, not just node-type bag)."""
    feats = Counter()
    for before, after in parse_hunks(a['fd']):
        tb, ta = try_parse(before), try_parse(after)
        eb, ea = edge_bag(tb), edge_bag(ta)
        ins = ea - eb
        dele = eb - ea
        for t, cnt in ins.items():
            feats[('INS', t)] += cnt
        for t, cnt in dele.items():
            feats[('DEL', t)] += cnt
    if not feats:
        feats[('NOEDIT', 'X')] = 1
    return feats

def sig_tree_edit_combo(a, ctx):
    """Node-type INS/DEL + edge INS/DEL fused."""
    out = Counter()
    for k, v in sig_tree_edit(a, ctx).items():
        out[('N',) + k] += v
    for k, v in sig_tree_edit_edges(a, ctx).items():
        out[('E',) + k] += v
    return out

def sig_tree_edit_typeonly(a, ctx):
    """Coarsest: the SET of edit-operation tokens (presence, not count) — pure structural class."""
    s = set()
    for k in sig_tree_edit(a, ctx):
        s.add(f'{k[0]}:{k[1]}')
    return s if s else {'EMPTY'}

# ---------------- run the BAR ----------------
SIGS = [
    ('LEXICAL-trigram(baseline)', lambda a, ctx: H.lexical_vsa(a['fd']), True),
    ('ast_tree_edit(node ins/del)', sig_tree_edit, True),
    ('ast_tree_edit_edges', sig_tree_edit_edges, True),
    ('ast_tree_edit_combo', sig_tree_edit_combo, True),
    ('ast_tree_edit_typeonly(set)', sig_tree_edit_typeonly, True),
]

print(f"{'signature':32s} {'recall@FP0':>11s} {'sep':>8s} {'ff':>7s} {'fc':>7s} {'nbugs':>6s}  verdict")
print("-" * 88)
lex = None
results = {}
for name, fn, legal in SIGS:
    r = H.evaluate(name, fn, [dict(x) for x in A], C, applytime_legal=legal, verbose=False)
    results[name] = r
    if name.startswith('LEXICAL'):
        lex = r['recall_fp0']
    rec = r['recall_fp0']
    passes = (rec is not None and rec > 0.25 and (lex is None or rec > lex))
    rs = ('%.4f' % rec) if rec is not None else 'n/a'
    print(f"{name:32s} {rs:>11s} {r['sep']:+.4f} {r['xbug_failed_failed']:7.4f} "
          f"{r['xbug_failed_correct']:7.4f} {r['n_bugs']:6d}  {'*** PASS' if passes else 'fail'}")
print("-" * 88)
print(f"BAR: recall@FP0 > 0.25 AND > lexical({lex:.4f}), model-free, applytime-legal.")

# diagnostics: parse coverage + token diversity (to honestly explain any null)
n_parsed_hunks = 0
n_total_hunks = 0
edit_tokens = Counter()
for a in A:
    for before, after in parse_hunks(a['fd']):
        n_total_hunks += 1
        tb, ta = try_parse(before), try_parse(after)
        if tb is not None or ta is not None:
            n_parsed_hunks += 1
    for k in sig_tree_edit(a, ctx={}):
        edit_tokens[k] += 1
print(f"\nDIAGNOSTICS: hunks parsed = {n_parsed_hunks}/{n_total_hunks} "
      f"({100.0*n_parsed_hunks/max(n_total_hunks,1):.1f}%)")
print(f"distinct edit-op tokens (node ins/del): {len(edit_tokens)}")
print("top-15 edit-op tokens:", edit_tokens.most_common(15))

# Print best result for the structured-output fields
best_name = max(results, key=lambda n: (results[n]['recall_fp0'] or 0) if not n.startswith('LEXICAL') else -1)
br = results[best_name]
print(f"\nBEST non-baseline: {best_name}  recall_fp0={br['recall_fp0']}  sep={br['sep']:+.4f}")
