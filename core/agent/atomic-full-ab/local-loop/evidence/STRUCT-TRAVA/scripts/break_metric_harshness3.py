#!/usr/bin/env python3
"""ATTACK metric_harshness — STAGE 3: final honest table.
Tie-correct robust recall at FP=0/1/5%, AUC + cluster-bootstrap CI, vs lexical.
A structural sig CRACKS the null iff (robust r@FP5 > 0.25 AND > lexical r@FP5) OR
(AUC CI lower bound > 0.5 AND > lexical AUC) for an APPLY-TIME-LEGAL, NON-degenerate sig."""
import numpy as np
from collections import defaultdict
import trava_harness as H
import sweep as SW

A, C = H.load(); D = H.D

def lobo(fn, attempts, ctx):
    def enc(a):
        r = fn(a, ctx)
        if r and isinstance(r, list) and len(r) == D and isinstance(r[0], (int, float)): return r
        return H.encode_tokens(r if r is not None else [])
    M = np.array([enc(a) for a in attempts], dtype=np.float64)
    S = np.nan_to_num((M @ M.T)/D)
    iid = np.array([a['iid'] for a in attempts])
    isfail = np.array([a['gp'] is not True for a in attempts]); iscorr = ~isfail
    N = len(attempts); by=defaultdict(list)
    for k,a in enumerate(attempts):
        if a['gp'] is not True: by[a['iid']].append(k)
    bugs=[b for b,v in by.items() if len(v)>=2]
    tp,tpb,fp,fpb=[],[],[],[]
    for h in bugs:
        bank=np.array([k for k in range(N) if isfail[k] and iid[k]!=h])
        if bank.size==0: continue
        for t in [k for k in range(N) if isfail[k] and iid[k]==h]: tp.append(float(S[t,bank].max())); tpb.append(h)
        for c in [k for k in range(N) if iscorr[k] and iid[k]==h]: fp.append(float(S[c,bank].max())); fpb.append(h)
    nd=len(set(tuple(np.sign(M[k]).astype(int)) for k in range(N)))
    return np.array(tp),tpb,np.array(fp),fpb,nd

def rr(tp,fp,rate):
    if len(tp)==0: return float('nan')
    if len(fp)==0: return 1.0
    cands=np.unique(np.concatenate([fp,[fp.max()+1e-9]])); best=0.0
    for thr in cands:
        if (fp>=thr).mean()<=rate+1e-12: best=max(best,(tp>=thr).mean())
    return float(best)

def auc(tp,fp):
    if len(tp)==0 or len(fp)==0: return float('nan')
    v=np.concatenate([tp,fp]); o=v.argsort(kind='mergesort'); sv=v[o]; r=np.empty(len(v)); i=0
    while i<len(sv):
        j=i
        while j+1<len(sv) and sv[j+1]==sv[i]: j+=1
        r[i:j+1]=(i+j)/2+1; i=j+1
    rk=np.empty(len(v)); rk[o]=r; nt=len(tp); U=rk[:nt].sum()-nt*(nt+1)/2
    return U/(nt*len(fp))

rng=np.random.default_rng(0)
lex=None; results=[]
print(f"{'signature':30s} {'legal':6s} {'deg?':>5s} {'AUC':>6s} {'AUClo':>6s} {'rr@0':>6s} {'rr@1':>6s} {'rr@5':>6s}")
print("-"*92)
for name,fn,legal in SW.SIGS:
    tp,tpb,fp,fpb,nd=lobo(fn,[dict(x) for x in A],C)
    a=auc(tp,fp)
    tpby=defaultdict(list); fpby=defaultdict(list)
    for v,b in zip(tp,tpb): tpby[b].append(v)
    for v,b in zip(fp,fpb): fpby[b].append(v)
    bugs=sorted(set(tpb+fpb)); aucs=[]
    for _ in range(400):
        s=rng.choice(len(bugs),len(bugs),replace=True); st=[];sf=[]
        for ix in s: st+=tpby[bugs[ix]]; sf+=fpby[bugs[ix]]
        if st and sf: aucs.append(auc(np.array(st),np.array(sf)))
    lo=np.percentile(aucs,2.5) if aucs else float('nan')
    r0,r1,r5=rr(tp,fp,0.0),rr(tp,fp,0.01),rr(tp,fp,0.05)
    deg = 'YES' if nd < 0.3*len(A) else 'no'   # >70% vector collapse = degenerate
    row=dict(name=name,legal=legal,deg=deg,auc=a,lo=lo,r0=r0,r1=r1,r5=r5)
    results.append(row)
    if name.startswith('LEXICAL'): lex=row
    print(f"{name[:30]:30s} {str(legal):6s} {deg:>5s} {a:6.3f} {lo:6.3f} {r0:6.3f} {r1:6.3f} {r5:6.3f}")
print("-"*92)
print(f"LEXICAL: AUC={lex['auc']:.3f} (CI_lo {lex['lo']:.3f}) rr@FP0={lex['r0']:.3f} rr@FP1={lex['r1']:.3f} rr@FP5={lex['r5']:.3f}")
print()
cracks=[]
for r in results:
    if r['name'].startswith('LEXICAL') or r['legal'] is False or r['deg']=='YES': continue
    by_recall = (np.isfinite(r['r5']) and r['r5']>0.25 and r['r5']>lex['r5'])
    by_auc    = (np.isfinite(r['lo']) and r['lo']>0.5 and r['auc']>lex['auc'])
    if by_recall or by_auc: cracks.append((r['name'], 'recall' if by_recall else 'auc'))
print(f"NON-degenerate apply-time-legal structural CRACKS under fair metrics: {cracks if cracks else 'NONE'}")
print()
print("Honest fair conclusion:")
print(f"  - Best apply-time AUC among non-degenerate sigs vs lexical {lex['auc']:.3f}:")
nd_legal=[r for r in results if r['legal'] and r['deg']=='no' and not r['name'].startswith('LEXICAL')]
for r in sorted(nd_legal,key=lambda x:-x['auc'])[:3]:
    print(f"      {r['name']:24s} AUC={r['auc']:.3f} CI_lo={r['lo']:.3f}  (CI {'excludes' if r['lo']>0.5 else 'INCLUDES'} 0.5)")
