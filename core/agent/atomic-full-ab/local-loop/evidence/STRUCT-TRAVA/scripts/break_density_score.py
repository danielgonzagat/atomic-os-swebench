#!/usr/bin/env python3
"""Final untried attack: the harness scores a move by MAX similarity to the failed bank (1-NN). That is exactly
what gets poisoned by one boilerplate-identical correct/failed pair. An honest, leak-free alternative scoring
rule is k-NN DENSITY: a move is 'in the failed manifold' if its mean similarity to its top-k failed-bank
neighbours is high. This is still a SOUND trava (we recompute the FP0 threshold under the SAME rule on held-out
correct moves), still model-free, still cross-bug. If density separates where 1-NN does not, the null cracks.
We test lexical + the 3 highest-sep discrete sigs (U4,U5,U6) under kNN-mean scoring for k in {3,5,10}."""
import re, io, tokenize
from collections import Counter, defaultdict
import numpy as np
import trava_harness as H

A, C = H.load(); D = H.D
_STOP = set('the a an of to in is be on for and or not this that with as by from at it if def class self return'.split())
def _idents(line):
    try: return [t.string for t in tokenize.generate_tokens(io.StringIO(line).readline)
                 if t.type == tokenize.NAME and t.string not in H.PYKW]
    except Exception: return [w for w in re.findall(r'[A-Za-z_]\w*', line) if w not in H.PYKW]
def sig_ident_reuse(a, ctx):
    add, rem = H.diff_added_removed(a['fd'])
    ai = Counter(i for l in add for i in _idents(l)); ri = Counter(i for l in rem for i in _idents(l))
    intro = set(ai)-set(ri); drop = set(ri)-set(ai); kept = set(ai)&set(ri); tot = len(intro)+len(kept)+1
    return Counter({f'NEW_{min(len(intro),6)}':1, f'DROP_{min(len(drop),6)}':1, f'KEPT_{min(len(kept),6)}':1,
                    f'NEWRATE_{round(len(intro)/tot,1)}':1})
def sig_problem_edit_bind(a, ctx):
    ps = (ctx['problem'].get(a['iid'],'') or '').lower()
    pw = set(w for w in re.findall(r'[a-z_]{3,}', ps) if w not in _STOP)
    add, rem = H.diff_added_removed(a['fd']); ids = set(i.lower() for l in add for i in _idents(l))
    on = ids & pw; off = ids - pw; tot = len(ids)+1; f = Counter({f'ONTOPIC_{round(len(on)/tot,1)}':1, f'NON_{min(len(off),6)}':1})
    at = ' '.join(add).lower()
    for kw in ('error','exception','none','empty','raise','default','missing','attribute','type','value','key','index'):
        if kw in ps and kw in at: f['BOTH:'+kw]+=1
    return f
def sig_hunk_geometry(a, ctx):
    diff=a['fd']; hunks=re.findall(r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@', diff); nf=len(H.diff_files(diff))
    f=Counter({f'NHUNK_{min(len(hunks),8)}':1, f'NFILE_{min(nf,4)}':1}); st=sorted(int(h[0]) for h in hunks if h[0])
    if len(st)>=2: f[f'SPAN_{min((st[-1]-st[0])//50,8)}']+=1; f['MULTIHUNK']+=1
    elif len(st)==1: f['SINGLEHUNK']+=1
    return f

def eval_knn(name, encode_fn, ks=(1,3,5,10)):
    Ac=[dict(x) for x in A]
    for a in Ac:
        r=encode_fn(a,C); a['_v']= r if (r and isinstance(r,list) and len(r)==D) else H.encode_tokens(r)
    M=np.array([a['_v'] for a in Ac],dtype=np.float64); S=np.nan_to_num((M@M.T)/D)
    iid=np.array([a['iid'] for a in Ac]); isf=np.array([a['gp'] is not True for a in Ac]); isc=~isf; N=len(Ac)
    bb=defaultdict(list)
    for k,a in enumerate(Ac):
        if a['gp'] is not True: bb[a['iid']].append(k)
    bugs=[b for b,v in bb.items() if len(v)>=2]
    print(name)
    for k in ks:
        tp,fp=[],[]
        for held in bugs:
            bank=np.array([j for j in range(N) if isf[j] and iid[j]!=held])
            if bank.size==0: continue
            def score(i):
                s=np.sort(S[i,bank])[::-1][:k]; return float(s.mean())
            for t in [j for j in range(N) if isf[j] and iid[j]==held]: tp.append(score(t))
            for c in [j for j in range(N) if isc[j] and iid[j]==held]: fp.append(score(c))
        if not fp: continue
        thr=max(fp)+1e-9; rec=sum(1 for s in tp if s>=thr)/len(tp) if tp else 0.0
        print('   k=%-2d  recall_fp0=%.3f  (thr=%.3f, max_fp=%.3f)' % (k, rec, thr, max(fp)))

eval_knn('LEXICAL', lambda a,ctx: H.lexical_vsa(a['fd']))
eval_knn('U4_ident_reuse', sig_ident_reuse)
eval_knn('U5_problem_edit_bind', sig_problem_edit_bind)
eval_knn('U6_hunk_geometry', sig_hunk_geometry)
print('\nBAR: recall_fp0 > 0.25 AND > lexical(k=1)=0.126, model-free, SOUND (FP0).')
