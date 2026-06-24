#!/usr/bin/env python3
"""ANGLE: dataflow_defuse — encode the DATA-FLOW / def-use relationship of the edit.

Model-free, deterministic, APPLY-TIME legal (uses only the diff text: added/removed lines + hunk
context). For each changed line we parse a name-agnostic def-use structure via Python's `ast` on the
single line (with light repair), then derive ROLE tokens:

  - DEF roles : a name is DEFINED (assign LHS, aug-assign, for-target, with-as, comprehension target,
                def-param, walrus). Abstracted to the *kind* of def, not the name.
  - USE roles : a name is USED (Name load, attribute base, call func, subscript value/index). Abstracted.
  - DEF/USE coupling within the change: does an ADDED line USE a name that an ADDED/context line DEFINES
    (intra-edit dataflow), or guard a None-able binding, etc.

We try several encodings and report the REAL recall_fp0 / sep from H.evaluate for each.
The BAR: recall_fp0 > 0.25 AND > 0.126 (lexical). We do NOT fabricate a pass.
"""
import ast, io, re, tokenize
from collections import Counter
import trava_harness as H

A, C = H.load()
LEX = 0.126


# ---------- name-agnostic def-use extraction from one source line ----------
def _try_parse(line):
    """Parse a single (possibly fragment) line into an AST. Returns ast.Module or None."""
    s = line.rstrip()
    # strip leading indentation so it parses as a statement
    s2 = s.lstrip()
    if not s2:
        return None
    # try plain
    for candidate in (s2,
                      s2 + "\n    pass" if s2.endswith(":") else None,
                      "_ = " + s2,           # bare expression / dangling
                      ):
        if candidate is None:
            continue
        try:
            return ast.parse(candidate)
        except Exception:
            continue
    return None


def _defs_uses(tree):
    """Return (defs:set[str], uses:set[str]) of names from an AST, plus structural role tokens."""
    defs, uses, roles = set(), set(), Counter()
    if tree is None:
        return defs, uses, roles
    for node in ast.walk(tree):
        # --- DEF sites ---
        if isinstance(node, ast.Assign):
            roles['DEF_ASSIGN'] += 1
            for tgt in node.targets:
                for n in ast.walk(tgt):
                    if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Store):
                        defs.add(n.id)
                    if isinstance(n, ast.Attribute) and isinstance(n.ctx, ast.Store):
                        roles['DEF_ATTR'] += 1
                    if isinstance(n, ast.Subscript) and isinstance(n.ctx, ast.Store):
                        roles['DEF_SUBSCR'] += 1
                    if isinstance(n, (ast.Tuple, ast.List)) and isinstance(getattr(n, 'ctx', None), ast.Store):
                        roles['DEF_UNPACK'] += 1
        elif isinstance(node, ast.AugAssign):
            roles['DEF_AUGASSIGN'] += 1
            for n in ast.walk(node.target):
                if isinstance(n, ast.Name):
                    defs.add(n.id)
        elif isinstance(node, ast.AnnAssign):
            roles['DEF_ANNASSIGN'] += 1
            if isinstance(node.target, ast.Name):
                defs.add(node.target.id)
        elif isinstance(node, ast.NamedExpr):  # walrus
            roles['DEF_WALRUS'] += 1
            if isinstance(node.target, ast.Name):
                defs.add(node.target.id)
        elif isinstance(node, ast.For):
            roles['DEF_FORTARGET'] += 1
            for n in ast.walk(node.target):
                if isinstance(n, ast.Name):
                    defs.add(n.id)
        elif isinstance(node, ast.comprehension):
            roles['DEF_COMP'] += 1
            for n in ast.walk(node.target):
                if isinstance(n, ast.Name):
                    defs.add(n.id)
        elif isinstance(node, ast.withitem):
            if node.optional_vars is not None:
                roles['DEF_WITHAS'] += 1
                for n in ast.walk(node.optional_vars):
                    if isinstance(n, ast.Name):
                        defs.add(n.id)
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            roles['DEF_FUNC'] += 1
            for arg in node.args.args + node.args.kwonlyargs:
                defs.add(arg.arg)

        # --- USE sites ---
        if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load):
            uses.add(node.id)
        if isinstance(node, ast.Attribute) and isinstance(node.ctx, ast.Load):
            roles['USE_ATTR'] += 1
            # attribute chain depth
        if isinstance(node, ast.Subscript) and isinstance(node.ctx, ast.Load):
            roles['USE_SUBSCR'] += 1
        if isinstance(node, ast.Call):
            roles['USE_CALL'] += 1
            if node.keywords:
                roles['USE_KWARG'] += 1
        if isinstance(node, ast.Compare):
            roles['USE_COMPARE'] += 1
            # None comparison?
            for cmp in node.comparators + [node.left]:
                if isinstance(cmp, ast.Constant) and cmp.value is None:
                    roles['CMP_NONE'] += 1
        if isinstance(node, ast.BoolOp):
            roles['USE_BOOLOP'] += 1
        if isinstance(node, ast.IfExp):
            roles['USE_TERNARY'] += 1
        if isinstance(node, ast.Return):
            roles['HAS_RETURN'] += 1
    return defs, uses, roles


def line_defuse(line):
    return _defs_uses(_try_parse(line))


# ============================================================
# SIGNATURE VARIANTS
# ============================================================

def sig_defuse_basic(a, ctx):
    """Bag of name-agnostic def/use role tokens over ADD and DEL lines."""
    add, rem = H.diff_added_removed(a['fd'])
    feats = Counter()
    for role, lines in (('ADD', add), ('DEL', rem)):
        for l in lines:
            d, u, r = line_defuse(l)
            for k, c in r.items():
                feats[f'{role}:{k}'] += c
            if d:
                feats[f'{role}:NDEF_{min(len(d),3)}'] += 1
            if u:
                feats[f'{role}:NUSE_{min(len(u),3)}'] += 1
    return feats


def sig_defuse_coupling(a, ctx):
    """The MISSION's core: cross-line def-use coupling within the edit.
    Does an ADDED line USE a name that is DEFINED by an ADDED/context line?  (true dataflow edit)
    Does the edit guard a None-able binding?  etc.  All name-agnostic."""
    add, rem = H.diff_added_removed(a['fd'])
    # also gather context (unchanged) lines around hunks for upstream defs
    ctx_lines = []
    for l in a['fd'].splitlines():
        if l[:3] in ('+++', '---') or l.startswith('@@') or l.startswith('diff '):
            continue
        if l.startswith(' '):
            ctx_lines.append(l[1:])

    add_defs, add_uses = set(), set()
    ctx_defs = set()
    rem_defs, rem_uses = set(), set()
    feats = Counter()
    for l in add:
        d, u, r = line_defuse(l)
        add_defs |= d
        add_uses |= u
    for l in rem:
        d, u, r = line_defuse(l)
        rem_defs |= d
        rem_uses |= u
    for l in ctx_lines:
        d, u, r = line_defuse(l)
        ctx_defs |= d

    # COUPLING role tokens (name-agnostic counts / booleans)
    # 1) added USE of a name defined upstream (context) -> "reads an existing binding"
    up = add_uses & ctx_defs
    if up:
        feats[f'ADD_USE_OF_CTXDEF_{min(len(up),3)}'] += 1
    # 2) added USE of a name defined within the same added block -> "new local dataflow"
    intra = add_uses & add_defs
    if intra:
        feats[f'ADD_USE_OF_ADDDEF_{min(len(intra),3)}'] += 1
    # 3) added def of a name that was previously used in removed/context -> "rebinds a consumed name"
    rebind = add_defs & (rem_uses | rem_defs)
    if rebind:
        feats[f'ADD_REDEF_{min(len(rebind),3)}'] += 1
    # 4) names that flow OUT: defined by add but not used in add (escape to downstream)
    escape = add_defs - add_uses
    if escape:
        feats[f'ADD_DEF_ESCAPE_{min(len(escape),3)}'] += 1
    # 5) pure-use add (reads only, defines nothing) vs pure-def
    if add_uses and not add_defs:
        feats['ADD_PURE_USE'] += 1
    if add_defs and not add_uses:
        feats['ADD_PURE_DEF'] += 1
    return feats


def sig_defuse_full(a, ctx):
    """basic role bag + coupling tokens, fused."""
    f = Counter()
    for k, c in sig_defuse_basic(a, ctx).items():
        f['B:' + k] += c
    for k, c in sig_defuse_coupling(a, ctx).items():
        f['C:' + k] += c
    return f


def sig_defuse_delta(a, ctx):
    """DELTA def-use: what the edit ADDS minus what it REMOVES at the role level.
    Captures 'this edit introduces a None-guard' / 'this edit adds an attribute-store' etc."""
    add, rem = H.diff_added_removed(a['fd'])
    add_r, rem_r = Counter(), Counter()
    for l in add:
        _, _, r = line_defuse(l)
        add_r += r
    for l in rem:
        _, _, r = line_defuse(l)
        rem_r += r
    feats = Counter()
    keys = set(add_r) | set(rem_r)
    for k in keys:
        delta = add_r[k] - rem_r[k]
        if delta > 0:
            feats[f'INTRO:{k}'] += min(delta, 3)
        elif delta < 0:
            feats[f'REMOVE:{k}'] += min(-delta, 3)
    return feats


def sig_defuse_signed(a, ctx):
    """Most discriminative attempt: name-agnostic def-use STRUCTURE of added lines only, with the
    'is this a same-RHS value-swap' vs 'is this a new control/dataflow' distinction. Combines
    delta-roles + coupling, drops the noisy DEL bag."""
    f = Counter()
    for k, c in sig_defuse_delta(a, ctx).items():
        f['D:' + k] += c
    for k, c in sig_defuse_coupling(a, ctx).items():
        f['C:' + k] += c
    return f


SIGS = [
    ('dataflow_defuse:basic', sig_defuse_basic),
    ('dataflow_defuse:coupling', sig_defuse_coupling),
    ('dataflow_defuse:full', sig_defuse_full),
    ('dataflow_defuse:delta', sig_defuse_delta),
    ('dataflow_defuse:signed', sig_defuse_signed),
]

print(f"{'signature':32s} {'recall@FP0':>11s} {'sep':>8s} {'ff':>7s} {'fc':>7s}  verdict")
print('-' * 80)
best = None
for name, fn in SIGS:
    r = H.evaluate(name, fn, [dict(x) for x in A], C, applytime_legal=True, verbose=False)
    rec = r['recall_fp0']
    passes = rec is not None and rec > 0.25 and rec > LEX
    if best is None or (rec or 0) > (best['recall_fp0'] or 0):
        best = r
    print(f"{name:32s} {('%.4f' % rec) if rec is not None else 'n/a':>11s} "
          f"{r['sep']:+.4f} {r['xbug_failed_failed']:7.4f} {r['xbug_failed_correct']:7.4f}  "
          f"{'*** PASS' if passes else 'fail'}")
print('-' * 80)
print(f"BAR: recall_fp0 > 0.25 AND > {LEX} (lexical).")
print(f"BEST: {best['name']} recall_fp0={best['recall_fp0']} sep={best['sep']:+.4f} thr={best['thr']}")
