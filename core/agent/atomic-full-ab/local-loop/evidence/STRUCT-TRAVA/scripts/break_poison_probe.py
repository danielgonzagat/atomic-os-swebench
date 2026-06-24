#!/usr/bin/env python3
"""Probe the 2-3 CORRECT moves that pin the lexical FP0 threshold at ~0.99 and kill recall.
Are they genuine (correct edit structurally ~= a cross-bug failed edit) or artifacts (near-empty/duplicate diffs)?
If artifacts, a leak-free dedup could legitimately lower the threshold -> honest recall could clear 0.25.
This is the only place the null could crack WITHOUT relaxing the soundness rule."""
import re
from collections import defaultdict
import numpy as np
import trava_harness as H

A, C = H.load()
D = H.D
Acpy = [dict(x) for x in A]
for a in Acpy: a['_v'] = H.lexical_vsa(a['fd'])
M = np.array([a['_v'] for a in Acpy], dtype=np.float64)
S = np.nan_to_num((M @ M.T) / D)
iid = np.array([a['iid'] for a in Acpy])
isfail = np.array([a['gp'] is not True for a in Acpy]); iscorr = ~isfail
N = len(Acpy)
by_bug = defaultdict(list)
for k, a in enumerate(Acpy):
    if a['gp'] is not True: by_bug[a['iid']].append(k)
bugs = [b for b, v in by_bug.items() if len(v) >= 2]

# For each held-out correct move, its max sim to the cross-bug failed bank + the matching failed neighbor
records = []
for held in bugs:
    bank = [k for k in range(N) if isfail[k] and iid[k] != held]
    bank_arr = np.array(bank)
    for c in [k for k in range(N) if iscorr[k] and iid[k] == held]:
        sims = S[c, bank_arr]
        j = int(np.argmax(sims))
        nb = bank[j]
        records.append((float(sims[j]), c, nb))
records.sort(reverse=True)
print('Top correct moves that poison the FP0 threshold (sim, correct_iid, matched_failed_iid):')
for s, c, nb in records[:6]:
    cdiff = Acpy[c]['fd']; ndiff = Acpy[nb]['fd']
    cadd, crem = H.diff_added_removed(cdiff); nadd, nrem = H.diff_added_removed(ndiff)
    ciid = Acpy[c]['iid']; niid = Acpy[nb]['iid']
    cfa = cadd[0][:80] if cadd else '<none>'
    nfa = nadd[0][:80] if nadd else '<none>'
    print('\n  sim=%.4f' % s)
    print('   CORRECT %s: +%d -%d lines, difflen=%d' % (ciid, len(cadd), len(crem), len(cdiff)))
    print('           first add: %r' % cfa)
    print('   FAILED  %s: +%d -%d lines, difflen=%d' % (niid, len(nadd), len(nrem), len(ndiff)))
    print('           first add: %r' % nfa)
    print('   identical_diff_text=%s' % (cdiff.strip() == ndiff.strip()))

# How many correct moves are tiny (likely near-no-op) that could legitimately deserve scrutiny?
print('\n--- correct-move diff sizes ---')
csz = sorted(len(Acpy[k]['fd']) for k in range(N) if iscorr[k])
print('correct diff lengths (sorted):', csz)
