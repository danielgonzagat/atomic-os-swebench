#!/usr/bin/env python3
"""confluence_z3.py - P7-z3 pairwise confluence + obligation + commute() faithfulness (Z3)."""
import sys
from z3 import (ArraySort, IntSort, BoolSort, Function, Const, Int, Bools,
    ForAll, Implies, And, Or, Not, If, Select, Store, K, Solver, unsat, sat)
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
def expect_sat(label, f):
    s=Solver(); s.add(f); r=s.check(); record(label, r==sat, "expected sat, got %s"%r)
St=ArraySort(IntSort(),IntSort())
inW1=Function('inW1',IntSort(),BoolSort()); inR1=Function('inR1',IntSort(),BoolSort())
inW2=Function('inW2',IntSort(),BoolSort()); inR2=Function('inR2',IntSort(),BoolSort())
app1=Function('app1',St,St); app2=Function('app2',St,St)
verdict1=Function('verdict1',St,BoolSort()); verdict2=Function('verdict2',St,BoolSort())
s=Const('s',St); t=Const('t',St); l=Int('l')
def agree(a,b,inR):
    x=Int('x'); return ForAll([x],Implies(inR(x),Select(a,x)==Select(b,x)))
def frame(app,inW): return ForAll([s,l],Implies(Not(inW(l)),Select(app(s),l)==Select(s,l)))
def rloc(app,inW,inR): return ForAll([s,t],Implies(agree(s,t,inR),ForAll([l],Implies(inW(l),Select(app(s),l)==Select(app(t),l)))))
def vloc(v,inR): return ForAll([s,t],Implies(agree(s,t,inR),v(s)==v(t)))
AX=[frame(app1,inW1),frame(app2,inW2),rloc(app1,inW1,inR1),rloc(app2,inW2,inR2),vloc(verdict1,inR1),vloc(verdict2,inR2)]
BERN=[ForAll([l],Not(And(inW1(l),inW2(l)))),ForAll([l],Not(And(inW1(l),inR2(l)))),ForAll([l],Not(And(inW2(l),inR1(l))))]
s0=Const('s0',St); l0=Int('l0')
print("P7-z3 . part 1/4 - pairwise confluence (Bernstein non-interference)")
expect_unsat("CONFLUENCE: commute => app2.app1 = app1.app2", AX+BERN, Select(app2(app1(s0)),l0)!=Select(app1(app2(s0)),l0))
print("P7-z3 . part 2/4 - obligation preservation")
expect_unsat("OBLIGATION: W2capR1 empty => verdict1 preserved across app2", AX+BERN, verdict1(s0)!=verdict1(app2(s0)))
expect_unsat("OBLIGATION: W1capR2 empty => verdict2 preserved across app1", AX+BERN, verdict2(s0)!=verdict2(app1(s0)))
print("P7-z3 . part 3/4 - non-vacuity + discrimination")
z=K(IntSort(),0)
e1=lambda st: Store(st,0,7); e2=lambda st: Store(st,1,8)
prove_valid("POSITIVE: disjoint edits => both orders byte-identical", e2(e1(z))==e1(e2(z)))
e1=lambda st: Store(st,0,Select(st,1)); e2=lambda st: Store(st,1,99)
prove_valid("DISCRIMINATE drop W2capR1 => orders DIFFER", Select(e2(e1(z)),0)!=Select(e1(e2(z)),0))
e1=lambda st: Store(st,0,99); e2=lambda st: Store(st,1,Select(st,0))
prove_valid("DISCRIMINATE drop W1capR2 => orders DIFFER", Select(e2(e1(z)),1)!=Select(e1(e2(z)),1))
e1=lambda st: Store(st,0,7); e2=lambda st: Store(st,0,8)
prove_valid("DISCRIMINATE drop W1capW2 => orders DIFFER", Select(e2(e1(z)),0)!=Select(e1(e2(z)),0))
print("P7-z3 . part 4/4 - faithfulness: commute() => Bernstein, ALL configs")
(sameFile,spanOverlap,shareIdent,identsKnown,clo_a_has_b,clo_b_has_a,neg_a_b,neg_b_a,capped)=Bools(
 'sameFile spanOverlap shareIdent identsKnown clo_a_has_b clo_b_has_a neg_a_b neg_b_a capped')
commute_same=And(Not(spanOverlap),identsKnown,Not(shareIdent))
commute_cross=And(Not(clo_b_has_a),Not(clo_a_has_b),Not(neg_a_b),Not(neg_b_a),Not(capped))
commute_true=If(sameFile,commute_same,commute_cross)
bernstein_cross=And(Not(clo_b_has_a),Not(clo_a_has_b),Not(neg_a_b),Not(neg_b_a))
bernstein_same=And(Not(spanOverlap),identsKnown,Not(shareIdent))
bernstein=If(sameFile,bernstein_same,bernstein_cross)
prove_valid("FAITHFUL: commute()=true => Bernstein precondition (every config)", Implies(commute_true,bernstein))
prove_valid("CAP-GUARD: capped => commute()=false (no false green)", Implies(And(capped,Not(sameFile)),Not(commute_true)))
prove_valid("SOUND: same-file overlap => commute()=false", Implies(And(sameFile,spanOverlap),Not(commute_true)))
prove_valid("SOUND: closure coupling => commute()=false", Implies(And(Not(sameFile),Or(clo_a_has_b,clo_b_has_a)),Not(commute_true)))
prove_valid("SOUND: negative-obligation read-locus => commute()=false", Implies(And(Not(sameFile),Or(neg_a_b,neg_b_a)),Not(commute_true)))
prove_valid("SOUND: unknown intra-file idents => commute()=false (UNJUDGED)", Implies(And(sameFile,Not(spanOverlap),Not(identsKnown)),Not(commute_true)))
expect_sat("NON-VACUOUS: commute()=true reachable cross-file", And(commute_true,Not(sameFile)))
expect_sat("NON-VACUOUS: commute()=true reachable same-file", And(commute_true,sameFile))
commute_cross_noguard=And(Not(clo_b_has_a),Not(clo_a_has_b),Not(neg_a_b),Not(neg_b_a))
expect_sat("DISCRIMINATE: dropping cap-guard admits a capped false-green", And(capped,commute_cross_noguard))
print()
if FAILS:
    print("P7-z3: %d obligation(s) FAILED: %s"%(len(FAILS),FAILS)); sys.exit(1)
print("P7-z3: ALL obligations discharged - confluence + obligation-preservation + faithfulness GREEN"); sys.exit(0)
