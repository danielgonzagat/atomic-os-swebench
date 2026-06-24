#!/usr/bin/env python3
"""Robustness: re-run with OFFICIAL SWE-bench resolved labels (71 resolved + 165 failed = 236 properly-labeled
attempts), not the thin 24 gate_pass=True. A correct move = its official harness run resolved the instance.
If the null holds with a non-degenerate FP wall, the boundary is decisive."""
import glob, json, re, os
import trava_harness as H

ROOT = H.ROOT
# join score_<base>.log -> resolved count, and its sibling <base>.json -> final_diff
labeled = []
for sl in glob.glob(f"{ROOT}/evidence/**/score_*.log", recursive=True):
    txt = open(sl, errors='ignore').read()
    m = re.search(r"Instances resolved:\s*(\d+)", txt)
    if not m: continue
    base = os.path.basename(sl)[len("score_"):-4]
    sib = os.path.join(os.path.dirname(sl), base + ".json")
    if not os.path.exists(sib): continue
    try: d = json.load(open(sib))
    except: continue
    fd = (d.get('final_diff') or '').strip()
    if not fd: continue
    iid = H._instance_of(d)
    if not iid: continue
    resolved = int(m.group(1)) >= 1
    labeled.append({'iid': iid, 'fd': fd, 'gp': True if resolved else False})

correct = sum(1 for a in labeled if a['gp'] is True)
print(f"officially-labeled attempts={len(labeled)}  resolved(correct)={correct}  failed={len(labeled)-correct}")
from collections import Counter
byb = Counter(a['iid'] for a in labeled)
bugs_both = [b for b in byb if any(x['iid']==b and x['gp'] for x in labeled) and any(x['iid']==b and not x['gp'] for x in labeled)]
print(f"distinct bugs={len(byb)}  bugs with BOTH a resolved and a failed attempt={len(bugs_both)}")

import os as _os
def edit_funcs(diff):
    return set(m for h in H.diff_hunk_headers(diff) for m in re.findall(r'(?:def|class)\s+([A-Za-z_]\w*)', h))
import sweep
SIGS = [
    ('LEXICAL-trigram', lambda a, ctx: H.lexical_vsa(a['fd']), True),
    ('moveshape', sweep.sig_moveshape, True),
    ('edit_op_taxonomy', sweep.sig_edit_op_taxonomy, True),
    ('keywords', sweep.sig_keywords, True),
    ('combined', sweep.sig_combined, True),
    ('edit_vs_gold(POSTHOC)', sweep.sig_edit_vs_gold, False),
]
A, C = H.load()   # for ctx (gold/tb)
print(f"\n{'signature':26s} {'recall@FP0':>11s} {'sep':>8s} {'ff':>6s} {'fc':>6s}")
print("-"*64)
lex = None
for name, fn, legal in SIGS:
    r = H.evaluate(name, fn, [dict(x) for x in labeled], C, applytime_legal=legal, verbose=False)
    if name.startswith('LEXICAL'): lex = r['recall_fp0']
    rec = r['recall_fp0']
    print(f"{name:26s} {('%.3f'%rec) if rec is not None else 'n/a':>11s} {r['sep']:+.3f} "
          f"{r['xbug_failed_failed']:6.3f} {r['xbug_failed_correct']:6.3f}")
print("-"*64)
print(f"BAR: recall@FP0 > 0.25 AND > lexical({lex:.3f}).  (official labels, {correct} correct / {len(bugs_both)} bugs with both classes)")
