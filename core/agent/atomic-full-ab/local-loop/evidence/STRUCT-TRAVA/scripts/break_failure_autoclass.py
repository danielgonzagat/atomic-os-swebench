#!/usr/bin/env python3
"""ANGLE: failure_autoclass — apply weights_autoclass.py union-find clustering (structural-locus collision:
shared file-basename AND shared func-name morpheme) to the FAILED diffs, then test whether the discovered
clusters predict held-out FAILED moves cross-bug at FP=0. A learned-but-model-free discretization.

Every number comes from running H.evaluate. The encoding is APPLY-TIME LEGAL: the structural-locus key is
extracted from the candidate diff itself (edited_units_from_diff), no gold, no model.

We test SEVERAL faithful operationalizations so the null (if it is one) is robust, not an artifact of one
encoding choice:
  V1 locus_raw      : encode the move by its raw structural-locus tokens (basenames + morphemes).
                      This is the per-move feature the autoclass COLLIDES on. If failed moves cross-bug share
                      a locus signature, VSA-sim picks it up.
  V2 cluster_id     : run autoclass on the FAILED bank, assign each failed move its discovered cluster-id,
                      encode the move by that cluster-id atom. Correct moves get the cluster-id of the
                      nearest-by-locus failed cluster (apply-time: a correct candidate would be routed to
                      whatever failure-cluster its locus collides with). The DISCRETIZATION itself is the signal.
  V3 cluster_inv    : encode by the cluster INVARIANT (intersection basenames+morphemes) — the name-agnostic
                      operator that capture_structural_operator emits. This is the literal "operator" the module
                      ships. A move is encoded by which cluster-invariant(s) its locus matches.
  V4 operator_match : the module's own operator_matches() predicate. For each move, does its locus match ANY
                      failure-cluster operator (file_hit AND morph_hit)? Encode the matched operator ids.
                      This is the most faithful to the module's intended generalization test.
"""
import os, sys, re
from collections import Counter, defaultdict
sys.path.insert(0, '/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop')
import weights_autoclass as W
import trava_harness as H

A, C = H.load()

# ---- precompute autoclass on the FAILED bank (the "learned" discretization) ----
fails = [a for a in A if a['gp'] is not True]
res = []
fail_units = {}
for i, a in enumerate(fails):
    eu = W.edited_units_from_diff(a['fd'])
    fail_units[i] = eu
    res.append({'id': i, 'edited_units': eu})
clusters = W.autoclass(res)

# map: failed-attempt-index -> cluster ordinal
member_to_cluster = {}
cluster_ops = []   # name-agnostic operator per cluster (from capture_structural_operator)
for cidx, c in enumerate(clusters):
    for m in c['members']:
        member_to_cluster[m] = cidx
    units_list = [fail_units[m] for m in c['members']]
    cluster_ops.append(W.capture_structural_operator(units_list))

# also a global locus->cluster lookup so CORRECT (and any) move can be routed by collision
def locus_of_diff(diff):
    eu = W.edited_units_from_diff(diff)
    return W.structural_locus_key(eu)


# ---------- V1: raw structural-locus tokens (the per-move feature autoclass collides on) ----------
def sig_locus_raw(a, ctx):
    k = locus_of_diff(a['fd'])
    toks = Counter()
    for b in k['basenames']:
        toks[('BASE', b)] += 1
    for m in k['morphemes']:
        toks[('MORPH', m)] += 1
    if not k['basenames'] and not k['morphemes']:
        toks[('LOCUS', 'EMPTY')] += 1
    return toks


# ---------- V2: discovered cluster-id (the discretization is the signal) ----------
# Build a routing index: which failure-cluster does an arbitrary locus collide with?
# collide = shared basename AND shared morpheme (the module's exact rule).
def route_to_clusters(k):
    hits = []
    for cidx, c in enumerate(clusters):
        inv = c['invariant']
        cb = set(inv['basenames']); cm = set(inv['morphemes'])
        # module rule needs BOTH non-empty intersections; empty-invariant clusters can't route anything
        if cb and cm and (set(k['basenames']) & cb) and (set(k['morphemes']) & cm):
            hits.append(cidx)
    return hits

def sig_cluster_id(a, ctx):
    k = locus_of_diff(a['fd'])
    hits = route_to_clusters(k)
    if not hits:
        return {('CLUSTER', 'NONE')}
    return {('CLUSTER', cidx) for cidx in hits}


# ---------- V3: cluster invariant operator (the name-agnostic operator the module ships) ----------
def sig_cluster_inv(a, ctx):
    k = locus_of_diff(a['fd'])
    toks = set()
    matched = False
    for op in cluster_ops:
        m = W.operator_matches(op, W.edited_units_from_diff(a['fd']))
        if m['matches']:
            matched = True
            for b in op['file_basenames']:
                toks.add(('OPBASE', b))
            for mo in op['name_morphemes']:
                toks.add(('OPMORPH', mo))
    if not matched:
        toks.add(('OP', 'NOMATCH'))
    return toks


# ---------- V4: operator_match predicate (module's own generalization check) ----------
def sig_operator_match(a, ctx):
    eu = W.edited_units_from_diff(a['fd'])
    toks = set()
    any_match = False
    for cidx, op in enumerate(cluster_ops):
        m = W.operator_matches(op, eu)
        if m['matches']:
            any_match = True
            toks.add(('MATCHOP', cidx))
    toks.add(('ANYMATCH', any_match))
    return toks


SIGS = [
    ('LEXICAL-trigram(baseline)', lambda a, ctx: H.lexical_vsa(a['fd']), True),
    ('V1 locus_raw', sig_locus_raw, True),
    ('V2 cluster_id', sig_cluster_id, True),
    ('V3 cluster_inv', sig_cluster_inv, True),
    ('V4 operator_match', sig_operator_match, True),
]

print(f"n_clusters(>=2)={len(clusters)}  "
      f"clusters_with_nonempty_invariant={sum(1 for c in clusters if c['invariant']['basenames'] and c['invariant']['morphemes'])}")
print()
print(f"{'signature':30s} {'recall@FP0':>11s} {'sep':>8s}  {'ff':>6s} {'fc':>6s}  verdict")
print("-" * 78)
lex = None
results = {}
for name, fn, legal in SIGS:
    r = H.evaluate(name, fn, [dict(x) for x in A], C, applytime_legal=legal, verbose=False)
    results[name] = r
    if name.startswith('LEXICAL'):
        lex = r['recall_fp0']
    rec = r['recall_fp0']
    passes = (rec is not None and rec > 0.25 and rec > (lex if lex is not None else 1.0))
    rec_s = ('%.3f' % rec) if rec is not None else '  n/a'
    print(f"{name:30s} {rec_s:>11s} {r['sep']:+.3f} {r['xbug_failed_failed']:6.3f} "
          f"{r['xbug_failed_correct']:6.3f}  {'*** PASS' if passes else 'fail'}")
print("-" * 78)
best = max((results[n] for n,_,_ in SIGS if not n.startswith('LEXICAL')),
           key=lambda r: (r['recall_fp0'] or 0.0))
print(f"BAR: recall@FP0 > 0.25 AND > lexical({lex:.3f}).")
print(f"BEST autoclass variant: {best['name']}  recall@FP0={best['recall_fp0']}  sep={best['sep']:+.3f}")
print(f"PASS? {best['recall_fp0'] is not None and best['recall_fp0'] > 0.25 and best['recall_fp0'] > lex}")
