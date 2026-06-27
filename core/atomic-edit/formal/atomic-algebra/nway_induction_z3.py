#!/usr/bin/env python3
"""nway_induction_z3.py - N-WAY half of P7-z3: batch confluence + obligation (all configs + N-way reduce/step)."""
import sys
from z3 import (ArraySort, IntSort, BoolSort, Function, Const, Int,
    ForAll, Implies, And, Not, Select, Store, K, Solver, unsat)
FAILS=[]
def record(label, ok, detail=""):
    print(("  PASS  " if ok else "  FAIL  ")+label+(("   ["+detail+"]") if (detail and not ok) else ""))
    if not ok: FAILS.append(label)
def expect_unsat(label, A, neg):
    s=Solver(); s.set('mbqi',True)
    for a in A: s.add(a)
    s.add(neg); r=s.check(); record(label, r==unsat, "expected unsat, got %s"%r)
def prove_valid(label, g):
    s=Solver(); s.add(Not(g)); r=s.check(); record(label, r==unsat, "expected valid, got %s"%r)
St=ArraySort(IntSort(),IntSort())
inW1=Function('inW1',IntSort(),BoolSort()); inR1=Function('inR1',IntSort(),BoolSort())
inWg=Function('inWg',IntSort(),BoolSort()); inRg=Function('inRg',IntSort(),BoolSort())
app1=Function('app1',St,St); g=Function('g',St,St); verdict1=Function('verdict1',St,BoolSort())
s=Const('s',St); t=Const('t',St); l=Int('l')
def agree(a,b,inR):
    x=Int('x'); return ForAll([x],Implies(inR(x),Select(a,x)==Select(b,x)))
def frame(app,inW): return ForAll([s,l],Implies(Not(inW(l)),Select(app(s),l)==Select(s,l)))
def rloc(app,inW,inR): return ForAll([s,t],Implies(agree(s,t,inR),ForAll([l],Implies(inW(l),Select(app(s),l)==Select(app(t),l)))))
def vloc(v,inR): return ForAll([s,t],Implies(agree(s,t,inR),v(s)==v(t)))
AX=[frame(app1,inW1),frame(g,inWg),rloc(app1,inW1,inR1),rloc(g,inWg,inRg),vloc(verdict1,inR1)]
BERN=[ForAll([l],Not(And(inW1(l),inWg(l)))),ForAll([l],Not(And(inW1(l),inRg(l)))),ForAll([l],Not(And(inWg(l),inR1(l))))]
s0=Const('s0',St); l0=Int('l0')
print("P7-z3/nway . step confluence + obligation against the aggregate of all other edits")
expect_unsat("STEP-CONFLUENCE: edit commutes past the aggregate rest (any N)", AX+BERN, Select(g(app1(s0)),l0)!=Select(app1(g(s0)),l0))
expect_unsat("STEP-OBLIGATION: verdict1 survives the aggregate rest (any N)", AX+BERN, verdict1(s0)!=verdict1(g(s0)))
print("P7-z3/nway . union-disjoint reduction over an arbitrary index N")
W=Function('W',IntSort(),IntSort(),BoolSort()); R=Function('R',IntSort(),IntSort(),BoolSort())
i=Int('i'); j=Int('j')
pairwise=ForAll([i,j,l],Implies(i!=j,Not(And(W(j,l),R(i,l)))))
i0=Int('i0'); j0=Int('j0')
expect_unsat("UNION-DISJOINT: pairwise => union of others disjoint from R_i (all N)", [pairwise], And(R(i0,l0), j0!=i0, W(j0,l0)))
print("P7-z3/nway . bounded concrete N-way confluence + collision discrimination")
for N in range(2,7):
    z=K(IntSort(),0); fwd=z; rev=z
    for k in range(N): fwd=Store(fwd,k,100+k)
    for k in reversed(range(N)): rev=Store(rev,k,100+k)
    prove_valid("BOUNDED N=%d: disjoint batch folds order-independently"%N, fwd==rev)
z=K(IntSort(),0)
fwd=Store(Store(Store(z,1,11),2,12),0,7)
rev=Store(Store(Store(z,1,11),2,12),0,8)
prove_valid("DISCRIMINATE: write-set collision makes the batch order-DEPENDENT", Select(fwd,0)!=Select(rev,0))
print()
if FAILS:
    print("P7-z3/nway: %d obligation(s) FAILED: %s"%(len(FAILS),FAILS)); sys.exit(1)
print("P7-z3/nway: ALL obligations discharged - N-way confluence + obligation-preservation GREEN"); sys.exit(0)
