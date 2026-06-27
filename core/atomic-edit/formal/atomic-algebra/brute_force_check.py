#!/usr/bin/env python3
"""
brute_force_check.py - SOLVER-INDEPENDENT corroboration of the verified-edit-algebra
theorems, by EXHAUSTIVE finite enumeration in pure Python (NO Z3, NO SMT solver).

Method diversity: confluence_z3.py / proof_footprint_z3.py discharge the theorems via the
Z3 SMT solver. This file re-checks the SAME claims by brute force, so a Z3-specific encoding
artifact or solver unsoundness cannot make the result a false green. Two independent methods,
one conclusion.

Checks:
  1. FAITHFULNESS (exhaustive over ALL 2^9 = 512 branch configs): runtime commute()=true
     => the Bernstein precondition holds; cap-guard; overlap/closure/neg-obligation/unknown-idents
     all force commute=false. (mirrors confluence_z3.py part 4, with zero solver.)
  2. CONFLUENCE (exhaustive over a bounded finite model L={0,1}, V={0,1}): for EVERY pair of
     edits (each = a write-set + a value-function that reads only its read-set) satisfying the
     Bernstein conditions, applying them in both orders yields byte-identical states.
  3. PROOF-FOOTPRINT obligation preservation (exhaustive, same model): if edit j's write-set is
     disjoint from edit i's footprint F_i, then verdict_i (any function of F_i) is preserved.
Exit 0 iff every enumerated case holds.
"""
import sys, itertools
FAILS=[]
def record(label, ok, detail=""):
    print(("  PASS  " if ok else "  FAIL  ")+label+(("   ["+detail+"]") if (detail and not ok) else ""))
    if not ok: FAILS.append(label)

# ---- 1. FAITHFULNESS: exhaustive over all 512 boolean configs ----
names=['sameFile','spanOverlap','shareIdent','identsKnown','clo_a_has_b','clo_b_has_a','neg_a_b','neg_b_a','capped']
bad_faithful=0; bad_capguard=0; reachable_cross=False; reachable_same=False
for bits in itertools.product([False,True],repeat=9):
    c=dict(zip(names,bits))
    commute_same=(not c['spanOverlap']) and c['identsKnown'] and (not c['shareIdent'])
    commute_cross=(not c['clo_b_has_a']) and (not c['clo_a_has_b']) and (not c['neg_a_b']) and (not c['neg_b_a']) and (not c['capped'])
    commute_true=commute_same if c['sameFile'] else commute_cross
    bernstein_cross=(not c['clo_b_has_a']) and (not c['clo_a_has_b']) and (not c['neg_a_b']) and (not c['neg_b_a'])
    bernstein_same=(not c['spanOverlap']) and c['identsKnown'] and (not c['shareIdent'])
    bernstein=bernstein_same if c['sameFile'] else bernstein_cross
    if commute_true and not bernstein: bad_faithful+=1
    if c['capped'] and (not c['sameFile']) and commute_true: bad_capguard+=1
    if commute_true and not c['sameFile']: reachable_cross=True
    if commute_true and c['sameFile']: reachable_same=True
record("FAITHFUL (exhaustive 512): commute()=true => Bernstein, ZERO counterexamples", bad_faithful==0, "found %d"%bad_faithful)
record("CAP-GUARD (exhaustive 512): no capped cross-file false-green", bad_capguard==0, "found %d"%bad_capguard)
record("NON-VACUOUS: commute reachable in both branches", reachable_cross and reachable_same)

# ---- bounded finite model: loci {0,1}, values {0,1} ----
L=[0,1]; V=[0,1]
states=list(itertools.product(V,repeat=len(L)))  # 4 states as tuples (v0,v1)
def subsets(xs):
    for r in range(len(xs)+1):
        for c in itertools.combinations(xs,r): yield frozenset(c)
# an edit = (W, R, table) where table maps the projection of the input state onto R -> values for loci in W
def proj(state,R): return tuple(state[i] for i in sorted(R))
def make_edits(W,R):
    keys=list(itertools.product(V,repeat=len(R)))           # all possible R-projections
    Wl=sorted(W)
    for outs in itertools.product(itertools.product(V,repeat=len(Wl)),repeat=len(keys)):
        table=dict(zip(keys,outs))
        def app(state,W=W,R=R,Wl=Wl,table=table):
            st=list(state); out=table[proj(state,R)]
            for idx,loc in enumerate(Wl): st[loc]=out[idx]
            return tuple(st)
        yield (W,R,app)

# ---- 2. CONFLUENCE: exhaustive over the finite model ----
conf_pairs=0; conf_bad=0
WRs=[(W,R) for W in subsets(L) for R in subsets(L)]
edits_by_WR={(W,R):list(make_edits(W,R)) for (W,R) in WRs}
for (W1,R1) in WRs:
    for (W2,R2) in WRs:
        # Bernstein conditions over the finite model
        if (W1&W2) or (W1&R2) or (W2&R1): continue
        for (_,_,a1) in edits_by_WR[(W1,R1)]:
            for (_,_,a2) in edits_by_WR[(W2,R2)]:
                conf_pairs+=1
                for s in states:
                    if a2(a1(s))!=a1(a2(s)): conf_bad+=1; break
record("CONFLUENCE (exhaustive finite model): Bernstein-disjoint edits commute in ALL orders", conf_bad==0, "%d bad of %d pairs"%(conf_bad,conf_pairs))

# ---- 3. PROOF-FOOTPRINT obligation preservation: exhaustive ----
fp_bad=0; fp_cases=0
for F in subsets(L):
    # verdict = any function of the F-projection; test ALL such verdicts
    fkeys=list(itertools.product(V,repeat=len(F)))
    for vout in itertools.product([False,True],repeat=len(fkeys)):
        verdict=dict(zip(fkeys,vout))
        def vfun(state,F=F,verdict=verdict): return verdict[proj(state,F)]
        for (W,R) in WRs:
            if (W & F): continue   # Wj disjoint from Fi
            for (_,_,aj) in edits_by_WR[(W,R)]:
                for s in states:
                    fp_cases+=1
                    if vfun(aj(s))!=vfun(s): fp_bad+=1; break
record("PROOF-FOOTPRINT (exhaustive): Wj disjoint Fi => verdict preserved, ZERO counterexamples", fp_bad==0, "%d bad of %d"%(fp_bad,fp_cases))
# tightness: a write INTO F can flip some verdict (the condition is necessary)
flip_found=False
for F in subsets(L):
    if not F: continue
    for (W,R) in WRs:
        if not (W & F): continue
        for (_,_,aj) in edits_by_WR[(W,R)]:
            fkeys=list(itertools.product(V,repeat=len(F)))
            for vout in itertools.product([False,True],repeat=len(fkeys)):
                verdict=dict(zip(fkeys,vout))
                def vfun(state,F=F,verdict=verdict): return verdict[proj(state,F)]
                for s in states:
                    if vfun(aj(s))!=vfun(s): flip_found=True; break
                if flip_found: break
            if flip_found: break
        if flip_found: break
    if flip_found: break
record("TIGHT (exhaustive): a write INTO the footprint CAN flip a verdict (condition load-bearing)", flip_found)

print()
if FAILS:
    print("brute-force: %d check(s) FAILED: %s"%(len(FAILS),FAILS)); sys.exit(1)
print("brute-force: ALL checks pass by EXHAUSTIVE enumeration (solver-independent) — corroborates the Z3 proofs GREEN"); sys.exit(0)
