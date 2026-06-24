#!/usr/bin/env python3
"""ANGLE: sequence_order — encode the ORDERED sequence of abstracted edit operations as a SHAPE
(VSA permutation-binding for position), not a bag. Two edits that perform the same abstract operations
in the same order collapse to the same vector; reordering or substituting an op breaks the match.

Model-free, deterministic. Every number from H.evaluate. APPLY-TIME legal (uses only the diff).

Design (the "ordered op-sequence shape"):
  1. Walk the diff in HUNK order, then line order. For each changed line, classify it into a coarse,
     name-AGNOSTIC OPERATION TOKEN (op-class) derived from H.abstract_line (identifiers->ID, NUM, STR,
     keywords/operators kept). This is the "edit operation" alphabet.
  2. Emit the ORDERED list of op-tokens for that attempt (the edit's shape-as-a-sequence).
  3. VSA-encode position via PERMUTATION binding: token at position i is bound to a position role by
     a deterministic permutation rho^i applied to the token atom (rho = a fixed random permutation of the
     2048 dims). bundle(rho^i(atom(op_i))) over the sequence. Sequence n-grams (bigrams/trigrams of the
     op-sequence) are also permutation-position-bound so that ORDER is what's captured, not the bag.

We test several granularities of the op alphabet + whether to include position at all, picking the encoder
that maximizes recall_fp0. All reported via H.evaluate; nothing claimed.
"""
import re, io, tokenize
import numpy as np
import trava_harness as H

A, C = H.load()
D = H.D

# ----- deterministic position permutation (rho) for VSA permutation-binding -----
import hashlib, random
def _perm():
    st = random.getstate()
    random.seed(int.from_bytes(hashlib.sha256(b'RHO:position-permutation').digest(), 'big'))
    p = list(range(D)); random.shuffle(p); random.setstate(st)
    return np.array(p, dtype=np.int64)
RHO = _perm()

def permute_pow(vec_arr, k):
    """Apply rho^k to a numpy vector by repeated index gather (k small; positions are bounded)."""
    out = vec_arr
    for _ in range(min(k, 24)):  # cap power so distant positions still differ but stay bounded
        out = out[RHO]
    return out

_atom_cache = {}
def atom_arr(t):
    if t not in _atom_cache:
        _atom_cache[t] = np.array(H.atom('OPSEQ:' + str(t)), dtype=np.float32)
    return _atom_cache[t]

# ----- op-classification of a single changed line (name-agnostic) -----
def op_class_fine(line):
    """Fine op token = the full abstracted line shape (tuple of name-agnostic tokens). Most specific."""
    ab = H.abstract_line(line)
    return ab if ab else None

def op_class_coarse(line):
    """Coarse op token = leading structural keyword + a small set of salient markers. Generalizes across bugs."""
    ab = H.abstract_line(line)
    if not ab: return None
    head = ab[0]
    kw = next((t for t in ab if t in H.PYKW), None)
    has_call = '(' in ab
    has_cmp = any(t in ('==','!=','<=','>=','<','>') for t in ab)
    has_assign = '=' in ab and not has_cmp
    has_attr = '.' in ab
    tag = []
    tag.append(f'H:{head}')
    if kw: tag.append(f'K:{kw}')
    if has_call: tag.append('CALL')
    if has_cmp: tag.append('CMP')
    if has_assign: tag.append('ASG')
    if has_attr: tag.append('ATTR')
    return tuple(tag)

def op_class_mid(line):
    """Mid op token = the keyword/operator skeleton of the line (drop ID/NUM/STR fillers, keep structure order)."""
    ab = H.abstract_line(line)
    if not ab: return None
    skel = tuple(t for t in ab if (t in H.PYKW or not (t == 'ID' or t == 'NUM' or t == 'STR')))
    return skel if skel else ('EMPTY',)

# ----- build the ordered op-sequence for an attempt (in diff order, with +/- role) -----
def op_sequence(diff, classifier):
    seq = []
    cur_sign = None
    for l in diff.splitlines():
        if l[:3] in ('+++', '---') or l.startswith('diff '): continue
        if l.startswith('@@'):
            seq.append('§HUNK§'); continue
        if l.startswith('+') and l[1:].strip():
            oc = classifier(l[1:])
            if oc: seq.append(('+', oc))
        elif l.startswith('-') and l[1:].strip():
            oc = classifier(l[1:])
            if oc: seq.append(('-', oc))
    return seq

# ----- VSA permutation-position encoding of the ordered op-sequence -----
def encode_seq_positional(seq):
    """bundle of rho^i(atom(op_i)) — position via permutation power. ORDER matters."""
    if not seq:
        return [0] * D
    acc = np.zeros(D, dtype=np.float32)
    for i, op in enumerate(seq):
        v = atom_arr(op)
        acc += permute_pow(v, i)
    return np.where(acc >= 0, 1, -1).astype(np.int8).tolist()

def encode_seq_ngram(seq, n=2):
    """ORDER captured via positional n-grams: each n-gram is a single atom (the ordered tuple), then
    each n-gram occurrence is permutation-bound by its start position. Pure sequence shape — a bag of the
    SAME ops in a different order produces different n-grams, hence a different vector."""
    if not seq:
        return [0] * D
    acc = np.zeros(D, dtype=np.float32)
    # unigrams (position-bound) + ngrams (position-bound)
    for i, op in enumerate(seq):
        acc += permute_pow(atom_arr(('1', op)), i)
    for k in range(2, n + 1):
        for i in range(len(seq) - k + 1):
            gram = tuple(seq[i:i + k])
            acc += permute_pow(atom_arr((str(k), gram)), i)
    return np.where(acc >= 0, 1, -1).astype(np.int8).tolist()

def encode_seq_ngram_nopos(seq, n=2):
    """ORDER via n-grams but WITHOUT absolute position (translation-invariant sequence shape). Two edits
    that do the same ops in the same RELATIVE order collapse even if offset within the diff."""
    if not seq:
        return [0] * D
    parts = []
    for k in range(1, n + 1):
        for i in range(len(seq) - k + 1):
            gram = tuple(seq[i:i + k])
            parts.append(np.array(H.atom('SEQNG:' + str((k, gram))), dtype=np.float32))
    if not parts:
        return [0] * D
    acc = np.sum(parts, axis=0)
    return np.where(acc >= 0, 1, -1).astype(np.int8).tolist()

# ----- candidate encoders -----
def mk(classifier_name, mode, n=2):
    cls = {'fine': op_class_fine, 'mid': op_class_mid, 'coarse': op_class_coarse}[classifier_name]
    def fn(a, ctx):
        seq = op_sequence(a['fd'], cls)
        if mode == 'pos':
            return encode_seq_positional(seq)
        if mode == 'ngram':
            return encode_seq_ngram(seq, n)
        if mode == 'ngram_nopos':
            return encode_seq_ngram_nopos(seq, n)
    return fn

CANDS = [
    ('seqorder/coarse/pos',          mk('coarse', 'pos')),
    ('seqorder/coarse/ngram2',       mk('coarse', 'ngram', 2)),
    ('seqorder/coarse/ngram3',       mk('coarse', 'ngram', 3)),
    ('seqorder/coarse/ngram2_nopos', mk('coarse', 'ngram_nopos', 2)),
    ('seqorder/coarse/ngram3_nopos', mk('coarse', 'ngram_nopos', 3)),
    ('seqorder/mid/pos',             mk('mid', 'pos')),
    ('seqorder/mid/ngram2',          mk('mid', 'ngram', 2)),
    ('seqorder/mid/ngram2_nopos',    mk('mid', 'ngram_nopos', 2)),
    ('seqorder/mid/ngram3_nopos',    mk('mid', 'ngram_nopos', 3)),
    ('seqorder/fine/ngram2_nopos',   mk('fine', 'ngram_nopos', 2)),
    ('seqorder/fine/pos',            mk('fine', 'pos')),
]

# baseline for reference (same run, same data)
lex = H.evaluate('LEXICAL-trigram', lambda a, ctx: H.lexical_vsa(a['fd']),
                 [dict(x) for x in A], C, applytime_legal=True, verbose=False)
LEX = lex['recall_fp0']

print(f"{'candidate':34s} {'recall@FP0':>11s} {'sep':>8s} {'ff':>7s} {'fc':>7s}  verdict")
print('-' * 86)
print(f"{'LEXICAL-trigram(baseline)':34s} {LEX:11.3f} {lex['sep']:+8.3f} "
      f"{lex['xbug_failed_failed']:7.3f} {lex['xbug_failed_correct']:7.3f}")
best = None
for name, fn in CANDS:
    r = H.evaluate(name, fn, [dict(x) for x in A], C, applytime_legal=True, verbose=False)
    rec = r['recall_fp0'] if r['recall_fp0'] is not None else 0.0
    passes = rec > 0.25 and rec > LEX
    if best is None or rec > best[1]:
        best = (name, rec, r)
    print(f"{name:34s} {rec:11.3f} {r['sep']:+8.3f} "
          f"{r['xbug_failed_failed']:7.3f} {r['xbug_failed_correct']:7.3f}  "
          f"{'*** PASS' if passes else 'fail'}")
print('-' * 86)
bn, brec, br = best
print(f"BEST: {bn}  recall@FP0={brec:.4f}  (BAR: >0.25 AND >lexical {LEX:.3f})")
print(f"PASS_BAR={brec > 0.25 and brec > 0.126}")
print(f"BEST_FULL={ {k: br[k] for k in ('name','recall_fp0','sep','xbug_failed_failed','xbug_failed_correct','thr','n_failed','n_correct','n_bugs')} }")
