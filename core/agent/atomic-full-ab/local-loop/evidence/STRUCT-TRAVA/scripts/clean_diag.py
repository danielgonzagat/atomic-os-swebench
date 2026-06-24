#!/usr/bin/env python3
"""Confound-free diagnostic: is there ANY cross-bug structural wrong-move signal?
Restrict BOTH similarities to CROSS-bug pairs; expose the same-bug confound separately.
Refined leave-one-bug-out: trava bank = OTHER bugs' failed moves (never the held bug's), so the FP wall
is set by held-out CORRECT moves only — no same-bug correct/failed near-duplicate artifact."""
import glob, json, re, io, tokenize, hashlib, random
from collections import defaultdict, Counter
D = 2048
ROOT = "/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"
_AC = {}
def atom(t):
    if t not in _AC:
        h = hashlib.sha256(('A:'+t).encode()).digest(); st=random.getstate(); random.seed(int.from_bytes(h,'big'))
        _AC[t]=[random.choice([1,-1]) for _ in range(D)]; random.setstate(st)
    return _AC[t]
def bundle(vs):
    if not vs: return [0]*D
    acc=[0]*D
    for v in vs: acc=[a+b for a,b in zip(acc,v)]
    return [1 if x>=0 else -1 for x in acc]
def sim(a,b): return sum(x*y for x,y in zip(a,b))/len(a) if a and b else 0.0
_CC={}
def _cv(c):
    if c not in _CC:
        h=hashlib.sha256(('C:'+c).encode()).digest(); st=random.getstate(); random.seed(int.from_bytes(h,'big'))
        _CC[c]=[random.choice([1,-1]) for _ in range(D)]; random.setstate(st)
    return _CC[c]
def lexical_vsa(text):
    if not text: return [0]*D
    text="_"+text.lower().strip()+"_"; acc=[0]*D
    for i in range(len(text)-2):
        tg=text[i:i+3]; v1,v2,v3=_cv(tg[0]),_cv(tg[1]),_cv(tg[2])
        tgv=[a*b*c for a,b,c in zip(v1[2:]+v1[:2], v2[1:]+v2[:1], v3)]
        acc=[x+y for x,y in zip(acc,tgv)]
    return [1 if x>=0 else -1 for x in acc]
PYKW=set("False None True and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield".split())
def abstract_line(line):
    toks=[]
    try:
        for tok in tokenize.generate_tokens(io.StringIO(line).readline):
            tt,ts=tok.type,tok.string
            if tt in (tokenize.NL,tokenize.NEWLINE,tokenize.INDENT,tokenize.DEDENT,tokenize.ENCODING,tokenize.ENDMARKER,tokenize.COMMENT): continue
            if tt==tokenize.NAME: toks.append(ts if ts in PYKW else "ID")
            elif tt==tokenize.NUMBER: toks.append("NUM")
            elif tt==tokenize.STRING: toks.append("STR")
            elif tt==tokenize.OP: toks.append(ts)
            elif ts.strip(): toks.append(ts)
    except Exception:
        for w in re.findall(r"[A-Za-z_]\w*|[=!<>+\-*/%]+|[():\[\].,]", line):
            toks.append(w if w in PYKW else ("ID" if re.match(r"[A-Za-z_]",w) else w))
    return tuple(toks)
def structural_vsa(diff):
    feats=Counter()
    for l in diff.splitlines():
        if l[:3] in ('+++','---') or l.startswith('@@') or l.startswith('diff '): continue
        role='ADD' if l.startswith('+') else 'DEL' if l.startswith('-') else None
        if not role: continue
        body=l[1:]
        if not body.strip(): continue
        ab=abstract_line(body)
        for t in ab:
            if t in PYKW or not t.isalnum(): feats[f"{role}:U:{t}"]+=1
        for a,b in zip(ab,ab[1:]): feats[f"{role}:B:{a}>{b}"]+=1
    parts=[atom(k) for k,c in feats.items() for _ in range(min(c,3))]
    return bundle(parts)
def instance_of(d):
    m=re.search(r'SWE-([\w.-]+__[\w.-]+-\d+)', d.get('task','')); return m.group(1) if m else None
attempts=[]
for f in glob.glob(f'{ROOT}/evidence/**/*.json',recursive=True):
    try: d=json.load(open(f))
    except: continue
    if not isinstance(d,dict): continue
    fd=(d.get('final_diff') or '').strip()
    if not fd: continue
    iid=instance_of(d)
    if not iid: continue
    attempts.append({'iid':iid,'fd':fd,'gp':d.get('gate_pass')})
for a in attempts: a['s']=structural_vsa(a['fd']); a['l']=lexical_vsa(a['fd'])
correct=[a for a in attempts if a['gp'] is True]
failed=[a for a in attempts if a['gp'] is not True]
print(f"attempts={len(attempts)} correct={len(correct)} failed={len(failed)}")
print(f"correct moves are on bugs: {Counter(a['iid'] for a in correct)}")

def mean(key, pred):
    tot=n=0.0
    for i in range(len(attempts)):
        for j in range(i+1,len(attempts)):
            a,b=attempts[i],attempts[j]
            if pred(a,b): tot+=sim(a[key],b[key]); n+=1
    return (tot/n if n else 0.0, int(n))
print("\n=== confound-free separation (CROSS-bug for both) ===")
for key,name in [('s','STRUCTURAL'),('l','LEXICAL')]:
    ff,nff=mean(key, lambda a,b: a['gp'] is not True and b['gp'] is not True and a['iid']!=b['iid'])
    fc,nfc=mean(key, lambda a,b: (a['gp'] is True)!=(b['gp'] is True) and a['iid']!=b['iid'])
    sb,nsb=mean(key, lambda a,b: (a['gp'] is True)!=(b['gp'] is True) and a['iid']==b['iid'])
    print(f"  {name:11s}: x-bug failed~failed={ff:.3f}(n={nff})  x-bug failed~correct={fc:.3f}(n={nfc})  "
          f"SAME-bug failed~correct={sb:.3f}(n={nsb})  | x-bug separation={ff-fc:+.3f}")

# refined leave-one-bug-out with GLOBAL threshold swept to FP=0 over held-out CORRECT moves
by_bug=defaultdict(list)
for a in failed: by_bug[a['iid']].append(a)
bugs=[b for b,v in by_bug.items() if len(v)>=2]
def loo(key):
    # for each candidate threshold, recall(TP on held failed) s.t. FP(block held correct)=0
    # build per-(held) best cross-bug sim for every failed and correct move
    tp_sims=[]; fp_sims=[]
    for held in bugs:
        bank=[a for a in failed if a['iid']!=held]
        for t in by_bug[held]:
            tp_sims.append(max(sim(t[key],b[key]) for b in bank))
        for c in [a for a in correct if a['iid']==held]:
            fp_sims.append(max(sim(c[key],b[key]) for b in bank))
    # threshold just above worst FP; if no held-out correct moves exist, FP undefined -> report block-rate@thr=0.5
    if fp_sims:
        thr=max(fp_sims)+1e-9
        rec=sum(1 for s in tp_sims if s>=thr)/len(tp_sims)
        return rec, thr, len(fp_sims)
    else:
        return None, None, 0
print("\n=== refined leave-one-bug-out recall@FP0 (FP wall = held-out bug's OWN correct moves) ===")
for key,name in [('s','STRUCTURAL'),('l','LEXICAL')]:
    rec,thr,nfp=loo(key)
    if rec is None: print(f"  {name}: no held-out correct moves to set FP wall (bugs with both classes absent)")
    else: print(f"  {name:11s}: recall@FP0={rec:.3f}  thr={thr:.3f}  (FP wall from {nfp} held-out correct moves)")
