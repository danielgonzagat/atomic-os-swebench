#!/usr/bin/env python3
"""ATTACK: are the gate_pass labels valid? Re-derive correct/incorrect from the OFFICIAL
SWE-bench score logs (evidence/**/score_*.log -> 'Instances resolved: N'), map each score
log to its attempt by (instance_id, exact model_patch) via the sibling pred_*.jsonl, then
re-run lexical + best structural signature with the re-labeled correct-set. Does the null hold?

Every number printed comes from running H.evaluate over the real attempts. No fabrication.
"""
import glob, re, os, json
import trava_harness as H

ROOT = "/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"

def norm(s): return (s or '').strip()
def inst_from_task(d):
    m = re.search(r'SWE-([\w.-]+__[\w.-]+-\d+)', d.get('task', '')); return m.group(1) if m else None

# ---- 1) Build official (iid, diff) -> resolved map from score+pred siblings ----
def build_official():
    off = {}
    nres = nunres = nskip = 0
    for s in glob.glob(f'{ROOT}/evidence/**/score_*.log', recursive=True):
        txt = open(s, errors='ignore').read()
        m = re.search(r'Instances resolved:\s*(\d+)', txt)
        sub = re.search(r'Instances submitted:\s*(\d+)', txt)
        if not m:
            nskip += 1; continue
        # only single-instance runs are unambiguous (all are, verified earlier)
        if sub and int(sub.group(1)) != 1:
            nskip += 1; continue
        resolved = int(m.group(1)) >= 1
        stem = os.path.basename(s)[len('score_'):-len('.log')]
        pred = os.path.join(os.path.dirname(s), f'pred_{stem}.jsonl')
        if not os.path.exists(pred):
            nskip += 1; continue
        try:
            rows = [json.loads(l) for l in open(pred) if l.strip()]
        except Exception:
            nskip += 1; continue
        if not rows:
            nskip += 1; continue
        r = rows[0]
        iid, patch = r.get('instance_id'), norm(r.get('model_patch'))
        if not iid or not patch:
            nskip += 1; continue
        key = (iid, patch)
        off[key] = off.get(key, False) or resolved   # resolved-wins on conflict
        if resolved: nres += 1
        else: nunres += 1
    return off, nres, nunres, nskip

OFF, NRES, NUNRES, NSKIP = build_official()

# ---- 2) Load harness attempts, attach official label ----
A, C = H.load()
covered = uncovered = flip_correct = flip_failed = agree = 0
for a in A:
    # reconstruct task->iid is already a['iid']; key on (iid, final_diff)
    key = (a['iid'], norm(a['fd']))
    official = OFF.get(key, None)
    a['_orig_gp'] = a['gp']
    a['_official'] = official
    if official is None:
        uncovered += 1
    else:
        covered += 1
        hc = (a['gp'] is True)
        if official and not hc: flip_correct += 1
        elif (not official) and hc: flip_failed += 1
        else: agree += 1

print("="*70)
print("OFFICIAL RE-LABELING (from score_*.log + pred_*.jsonl)")
print("="*70)
print(f"score logs: resolved={NRES} unresolved={NUNRES} skipped={NSKIP}")
print(f"harness attempts loaded: {len(A)}")
print(f"  matched to official label : {covered}")
print(f"  unmatched (kept as-is)    : {uncovered}")
print(f"  agree w/ harness          : {agree}")
print(f"  FLIP failed->CORRECT      : {flip_correct}  (harness mislabeled wins as fails)")
print(f"  FLIP correct->FAILED      : {flip_failed}")

orig_correct = sum(1 for a in A if a['_orig_gp'] is True)
print(f"\noriginal harness correct-set size : {orig_correct}")

# ---- 3) Apply official relabel: gp=True iff officially resolved; covered-unresolved -> False ----
def apply_relabel(attempts, mode):
    """mode='official_strict': use official where known, keep original elsewhere.
       mode='official_only'  : only attempts with an official label are kept (drop unmatched)."""
    out = []
    for a in attempts:
        b = dict(a)
        off = a['_official']
        if off is None:
            if mode == 'official_only':
                continue
            # keep original gp (unmatched -> treat as harness did)
            b['gp'] = a['_orig_gp']
        else:
            b['gp'] = True if off else False
        out.append(b)
    return out

# best structural signature available: per the null, lexical(0.126) was the ceiling; the strongest
# structural was moveshape(0.014). We re-run lexical AND moveshape AND tb_relation under relabel.
from collections import Counter
def sig_moveshape(a, ctx):
    add, rem = H.diff_added_removed(a['fd']); feats = Counter()
    for role, lines in (('ADD', add), ('DEL', rem)):
        for l in lines:
            ab = H.abstract_line(l)
            for t in ab:
                if t in H.PYKW or not t.isalnum(): feats[f"{role}:U:{t}"] += 1
            for x, y in zip(ab, ab[1:]): feats[f"{role}:B:{x}>{y}"] += 1
    return feats

SIGS = [
    ('LEXICAL-trigram', lambda a, ctx: H.lexical_vsa(a['fd']), True),
    ('moveshape',       sig_moveshape, True),
]

def run_block(title, attempts):
    ncorr = sum(1 for a in attempts if a['gp'] is True)
    nfail = sum(1 for a in attempts if a['gp'] is not True)
    print("\n" + "-"*70)
    print(f"{title}   (N={len(attempts)}, correct={ncorr}, failed={nfail})")
    print("-"*70)
    lex = None
    for name, fn, legal in SIGS:
        r = H.evaluate(name, fn, [dict(x) for x in attempts], C, applytime_legal=legal, verbose=False)
        if name.startswith('LEXICAL'): lex = r['recall_fp0']
        rec = r['recall_fp0']
        passes = (rec is not None and rec > 0.25 and (lex is None or (rec is not None and rec > lex)))
        recs = ('%.4f' % rec) if rec is not None else 'n/a'
        print(f"  {name:18s} recall@FP0={recs:>8s}  sep={r['sep']:+.4f} "
              f"ff={r['xbug_failed_failed']:+.4f} fc={r['xbug_failed_correct']:+.4f} "
              f"nbugs={r['n_bugs']:3d}  {'*** PASS' if passes else 'fail'}")
    return lex

# Baseline (ORIGINAL harness labels) for reference
run_block("BASELINE — original harness gp labels", [dict(x) for x in A])
# Relabeled, strict (official where known, original elsewhere)
run_block("RELABELED — official score logs (strict: keep unmatched as-is)", apply_relabel(A, 'official_strict'))
# Relabeled, official-only subset (drop unmatched — purest official-truth set)
run_block("RELABELED — official-only subset (drop unmatched attempts)", apply_relabel(A, 'official_only'))
