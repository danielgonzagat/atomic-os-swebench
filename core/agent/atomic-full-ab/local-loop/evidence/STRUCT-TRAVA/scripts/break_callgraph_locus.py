#!/usr/bin/env python3
"""ANGLE: callgraph_locus — place the edit-target in the intra-file call/def graph of the PRISTINE repo,
emit NAME-AGNOSTIC graph-role tokens (leaf/internal, fan-in/out buckets, depth, method/modfunc),
plus traceback-relative distance buckets (symptom = last tb frame) when a traceback exists.
MODEL-FREE: pure AST + diff + traceback. Every number from H.evaluate."""
import warnings; warnings.filterwarnings("ignore")
import os, re
from collections import defaultdict, deque
import cg_lib as G
import trava_harness as H

A, C = H.load()

# ---------- build an undirected call-name graph per file for symptom-distance ----------
def name_graph(g):
    """from (funcs,calls,defnames) build simplename adjacency (caller<->callee by simplename)."""
    funcs, calls, defnames = g
    adj = defaultdict(set)
    sn_of = {qn: funcs[qn][4] for qn in funcs}
    for qn, callees in calls.items():
        cs = sn_of.get(qn)
        for ce in callees:
            if ce in defnames:  # only intra-file edges
                adj[cs].add(ce); adj[ce].add(cs)
    return adj

def bfs_dist(adj, src, dsts):
    if src is None or not dsts: return None
    if src in dsts: return 0
    seen = {src}; q = deque([(src, 0)])
    while q:
        n, d = q.popleft()
        if d > 6: break
        for nb in adj.get(n, ()):
            if nb in dsts: return d + 1
            if nb not in seen:
                seen.add(nb); q.append((nb, d + 1))
    return None  # unreachable / too far

def edit_targets(a):
    """yield (funcs, calls, defnames, adj, ef_qn, simplename) for each resolved edit-target."""
    iid = a['iid']
    out = []
    for relpath, lns in G.diff_touched_lines(a['fd']).items():
        base = os.path.basename(relpath)
        p = G.pristine_path(iid, base, relpath)
        if not p: continue
        g = G.file_graph(p)
        if not g: continue
        funcs, calls, defnames = g
        adj = name_graph(g)
        for ln in lns:
            ef = G.enclosing_func(funcs, ln)
            if ef is None:
                out.append((funcs, calls, defnames, adj, None, None))
            else:
                out.append((funcs, calls, defnames, adj, ef, funcs[ef][4]))
    return out

# ---------- SIGNATURES ----------
def sig_locus_pure(a, ctx):
    """Pure graph-role of the edit-target (no traceback). Name-agnostic."""
    toks = set()
    for funcs, calls, defnames, adj, ef, sn in edit_targets(a):
        if ef is None:
            toks.add('MODULE_LEVEL'); continue
        lo, hi, ism, depth, _ = funcs[ef]
        fanout = len(calls.get(ef, set()) & set(defnames))   # intra-file callees
        fanin = sum(1 for q, cs in calls.items() if sn in cs and q != ef)
        toks.add('METHOD' if ism else 'MODFUNC')
        toks.add('LEAF' if fanout == 0 else 'INTERNAL')
        toks.add(f'FANIN_{G.bucket(fanin,[0,1,3,8])}')
        toks.add(f'FANOUT_{G.bucket(fanout,[0,2,5,12])}')
        toks.add(f'DEPTH_{min(depth,4)}')
        toks.add(f'SPAN_{G.bucket(hi-lo,[5,20,60,150])}')
    return toks

def sig_locus_symptom(a, ctx):
    """Apply-time legal: graph-DISTANCE from edit-target to traceback symptom/frames.
    Symptom = last tb frame func. Buckets: AT_SYMPTOM / DIST_k / UNREACHABLE / NO_TB."""
    frames = ctx['tb_frames'].get(a['iid'], [])
    base = sig_locus_pure(a, ctx)
    if not frames:
        base.add('NO_TB'); return base
    tb_funcs = set(fn for _, fn in frames)
    symptom = frames[-1][1]
    upstream = tb_funcs - {symptom}
    base.add('HAS_TB')
    for funcs, calls, defnames, adj, ef, sn in edit_targets(a):
        if sn is None: continue
        # is the edit-target ON the tb path?
        if sn == symptom: base.add('EDIT_AT_SYMPTOM')
        elif sn in upstream: base.add('EDIT_AT_UPSTREAM')
        d_sym = bfs_dist(adj, sn, {symptom})
        d_any = bfs_dist(adj, sn, tb_funcs)
        if d_sym is not None: base.add(f'DSYM_{G.bucket(d_sym,[0,1,2,4])}')
        else: base.add('DSYM_UNREACH')
        if d_any is not None: base.add(f'DTB_{G.bucket(d_any,[0,1,2,4])}')
        else: base.add('DTB_UNREACH')
    return base

def sig_locus_neighborhood(a, ctx):
    """Richer name-agnostic locus: also encode the SHAPE of the immediate call neighborhood
    (how many intra-file callees, distinct callee-roles), trying to make correct vs failed
    edits at the SAME function still differ by which sub-locus they touch. Combine with the
    diff's abstract operation so the vector isn't pure-locus (escape the within-bug collapse)."""
    toks = set(sig_locus_pure(a, ctx))
    # add abstract edit-op so co-located correct/failed moves can still diverge
    add, rem = H.diff_added_removed(a['fd'])
    for role, lines in (('A', add), ('D', rem)):
        for l in lines:
            for t in H.abstract_line(l):
                if t in H.PYKW: toks.add(f'{role}KW:{t}')
    return toks

if __name__ == "__main__":
    print(f"{'signature':30s} {'legal':6s} {'recall@FP0':>11s} {'sep':>8s} {'ff':>6s} {'fc':>6s}  verdict")
    print("-" * 84)
    # baseline first
    rlex = H.evaluate("LEXICAL", lambda a, c: H.lexical_vsa(a['fd']), [dict(x) for x in A], C, True, False)
    lex = rlex['recall_fp0']
    def show(name, fn, legal):
        r = H.evaluate(name, fn, [dict(x) for x in A], C, legal, False)
        rec = r['recall_fp0']
        passes = rec is not None and rec > 0.25 and rec > lex
        print(f"{name:30s} {str(legal):6s} {('%.3f'%rec) if rec is not None else 'n/a':>11s} "
              f"{r['sep']:+.3f} {r['xbug_failed_failed']:6.3f} {r['xbug_failed_correct']:6.3f}  "
              f"{'*** PASS' if passes else 'fail'}")
        return r
    show("LEXICAL(baseline)", lambda a, c: H.lexical_vsa(a['fd']), True)
    show("callgraph_locus_pure", sig_locus_pure, True)
    show("callgraph_locus_symptom", sig_locus_symptom, True)
    show("callgraph_locus_neighborhood", sig_locus_neighborhood, True)
    print("-" * 84)
    print(f"BAR: recall@FP0 > 0.25 AND > lexical({lex:.3f})")
