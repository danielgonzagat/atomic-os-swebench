#!/usr/bin/env python3
"""ANGLE: test_relation — relationship between the EDIT and the FAILING TEST/ASSERTION named in the problem text.

Model-free, deterministic, APPLY-TIME LEGAL (problem_statement is available at apply time; no gold used).

Idea: parse the issue's test/assertion hints from C['problem'][iid]:
  - exception/error/warning TYPE names (FooError, BarException, BazWarning)
  - the symbols (identifiers, attributes, callables) named in code blocks / backtick spans / assert lines /
    expected-vs-actual lines
  - the failing test function name(s) (def test_*)
Then encode RELATIONAL tokens describing whether the edit touches the symbol/exception the failing assertion
names. The hypothesis (the doctrine's 'trava'): a FAILED move tends to NOT touch the issue's named
symbol/exception (it edits something unrelated), and this 'mis-targeting relation' RE-OCCURS across bugs, so a
cross-bug bank of failed-move relation-vectors blocks a held-out failed move without ever blocking the correct
path (which DOES touch the named symbol).

Every number below comes from running H.evaluate (the BAR). No number is claimed.
"""
import re, os
from collections import Counter
import trava_harness as H

A, C = H.load()

# ---------------- parse the failing-test / assertion surface from the issue ----------------
ERR_RE = re.compile(r'\b([A-Z][A-Za-z0-9_]*(?:Error|Exception|Warning))\b')
TESTFN_RE = re.compile(r'\bdef\s+(test_\w+)')
IDENT_RE = re.compile(r'[A-Za-z_]\w+')

def _code_spans(text):
    """All code-ish spans of the issue: fenced blocks, inline backticks, traceback lines, >>> repl lines."""
    spans = []
    spans += re.findall(r'```[a-zA-Z]*\n(.*?)```', text, re.S)      # fenced blocks
    spans += re.findall(r'`([^`]+)`', text)                          # inline code
    spans += re.findall(r'^\s*>>>?\s?(.*)$', text, re.M)             # repl / continuation lines
    return spans

def issue_surface(text):
    """Return (err_types:set, symbols:set, test_fns:set) named in the failing-test/issue surface."""
    err = set(ERR_RE.findall(text))
    testfns = set(TESTFN_RE.findall(text))
    syms = set()
    for span in _code_spans(text):
        for w in IDENT_RE.findall(span):
            syms.add(w)
    # assertion-specific: tokens appearing on assert / expected / actual / got lines (stronger test-relation)
    assert_syms = set()
    for line in text.splitlines():
        if re.search(r'\b(assert|assertEqual|assertRaises|expected|Expected|but got|actual|Actual)\b', line):
            for w in IDENT_RE.findall(line):
                assert_syms.add(w)
    return err, syms, testfns, assert_syms

# precompute issue surface per bug
SURF = {}
for iid in set(a['iid'] for a in A):
    SURF[iid] = issue_surface(C['problem'][iid])

# stopword-ish python/common tokens that are not discriminative as "named symbol"
COMMON = set("""import from def class self return None True False print str int float list dict set tuple
type object len range for in if else elif while try except raise with as is not and or pass lambda
the a an of to and is be this that it value values name names test py python array array_ output input
expected actual got but should would could File line module stdin main""".split())

def edit_idents(diff):
    add, rem = H.diff_added_removed(diff)
    ids = set()
    for l in add + rem:
        for t in IDENT_RE.findall(l):
            ids.add(t)
    return ids

def edit_call_targets(diff):
    """Identifiers that appear as call targets `name(` or attribute access `.name` in added/removed lines."""
    add, rem = H.diff_added_removed(diff)
    calls, attrs = set(), set()
    for l in add + rem:
        calls |= set(re.findall(r'([A-Za-z_]\w*)\s*\(', l))
        attrs |= set(re.findall(r'\.([A-Za-z_]\w*)', l))
    return calls, attrs

def edit_raised(diff):
    """Exception types the edit raises/catches (raise Foo / except Foo)."""
    add, rem = H.diff_added_removed(diff)
    out = set()
    for l in add + rem:
        out |= set(re.findall(r'\b(?:raise|except)\s+([A-Z]\w*)', l))
    return out

def bucket(n, edges=(0, 1, 2, 4, 8)):
    for i, e in enumerate(edges):
        if n <= e:
            return i
    return len(edges)

# ---------------- the relational signature ----------------
def sig_test_relation(a, ctx):
    err, syms, testfns, assert_syms = SURF[a['iid']]
    syms = syms - COMMON
    assert_syms = assert_syms - COMMON
    eid = edit_idents(a['fd'])
    ecalls, eattrs = edit_call_targets(a['fd'])
    eraise = edit_raised(a['fd'])

    toks = set()

    # (1) does the edit touch ANY symbol the issue names?
    hit_sym = eid & syms
    toks.add('TOUCH_ISSUE_SYM' if hit_sym else 'MISS_ISSUE_SYM')
    toks.add(f'NTOUCH_SYM_{bucket(len(hit_sym))}')

    # (2) does the edit touch a symbol named on an ASSERT / expected / actual line specifically?
    hit_assert = eid & assert_syms
    toks.add('TOUCH_ASSERT_SYM' if hit_assert else 'MISS_ASSERT_SYM')

    # (3) does the edit call/attr-access an issue-named symbol (active use, not just mention)?
    if (ecalls | eattrs) & syms:
        toks.add('USE_ISSUE_SYM')
    else:
        toks.add('NO_USE_ISSUE_SYM')

    # (4) exception/error relation: issue names an error type — does the edit touch it?
    if err:
        toks.add('ISSUE_HAS_ERRTYPE')
        if eid & err:
            toks.add('EDIT_TOUCHES_ERRTYPE')
        else:
            toks.add('EDIT_IGNORES_ERRTYPE')
        if eraise & err:
            toks.add('EDIT_RAISES_ISSUE_ERR')
    else:
        toks.add('ISSUE_NO_ERRTYPE')

    # (5) failing-test relation: issue names a test fn — does the edit name it / a symbol it asserts?
    if testfns:
        toks.add('ISSUE_HAS_TESTFN')
        if eid & testfns:
            toks.add('EDIT_TOUCHES_TESTFN')

    # (6) fraction of edit's call-targets that are issue-grounded (mis-target relation, coarse-bucketed)
    if ecalls:
        grounded = len(ecalls & syms)
        toks.add(f'CALLGROUND_{bucket(grounded)}')

    return toks


# variant B: PURELY the relational predicate, no magnitude buckets (avoid encoding the edit's size)
def sig_test_relation_pure(a, ctx):
    err, syms, testfns, assert_syms = SURF[a['iid']]
    syms = syms - COMMON
    assert_syms = assert_syms - COMMON
    eid = edit_idents(a['fd'])
    ecalls, eattrs = edit_call_targets(a['fd'])
    toks = set()
    toks.add('TOUCH_ISSUE_SYM' if (eid & syms) else 'MISS_ISSUE_SYM')
    toks.add('TOUCH_ASSERT_SYM' if (eid & assert_syms) else 'MISS_ASSERT_SYM')
    toks.add('USE_ISSUE_SYM' if ((ecalls | eattrs) & syms) else 'NO_USE_ISSUE_SYM')
    if err:
        toks.add('EDIT_TOUCHES_ERRTYPE' if (eid & err) else 'EDIT_IGNORES_ERRTYPE')
    return toks


# variant C: relation as a WEIGHTED role-bind into the issue-symbol identity itself
# (binds the specific shared symbol so two failed moves that both mis-touch the SAME issue symbol bind together).
# Still apply-time legal. This is the strongest 'shared relation re-occurs' encoding.
def sig_test_relation_bound(a, ctx):
    err, syms, testfns, assert_syms = SURF[a['iid']]
    syms = syms - COMMON
    eid = edit_idents(a['fd'])
    feats = Counter()
    hit = eid & syms
    # role-bind on the PREDICATE class, value-agnostic to the bug (so cross-bug binding can occur)
    feats[('REL', 'TOUCH' if hit else 'MISS')] += 1
    feats[('REL', 'USE' if (edit_call_targets(a['fd'])[0] & syms) else 'NOUSE')] += 1
    if err:
        feats[('REL', 'ERRHIT' if (eid & err) else 'ERRMISS')] += 1
    # name-AGNOSTIC abstraction of WHICH structural kind of issue-symbol was hit/missed:
    # is the hit symbol an Error type? a Test fn? a CamelCase class? a lower_snake fn?
    def kindset(s):
        ks = set()
        for w in s:
            if w in err: ks.add('ERR')
            elif w in testfns: ks.add('TEST')
            elif w[:1].isupper(): ks.add('CLASS')
            elif '_' in w: ks.add('SNAKE')
            else: ks.add('NAME')
        return ks
    for k in kindset(hit):
        feats[('HITKIND', k)] += 1
    for k in kindset(syms - eid):  # kinds of issue-symbols the edit MISSED
        feats[('MISSKIND', k)] += 1
    return feats


if __name__ == "__main__":
    print(f"{'signature':36s} {'applytime':9s} {'recall@FP0':>11s} {'sep':>8s} {'ff':>6s} {'fc':>6s}  verdict")
    print("-" * 92)
    # baseline first
    lex = H.evaluate("LEXICAL-trigram(baseline)", lambda a, ctx: H.lexical_vsa(a['fd']),
                     [dict(x) for x in A], C, applytime_legal=True, verbose=False)
    lex_recall = lex['recall_fp0']
    def show(r, legal):
        rec = r['recall_fp0']
        passes = (rec is not None and rec > 0.25 and rec > lex_recall)
        print(f"{r['name']:36s} {str(legal):9s} {('%.3f'%rec) if rec is not None else '  n/a':>11s} "
              f"{r['sep']:+.3f} {r['xbug_failed_failed']:6.3f} {r['xbug_failed_correct']:6.3f}  "
              f"{'*** PASS' if passes else 'fail'}")
    show(lex, True)
    for name, fn in [('test_relation', sig_test_relation),
                     ('test_relation_pure', sig_test_relation_pure),
                     ('test_relation_bound', sig_test_relation_bound)]:
        r = H.evaluate(name, fn, [dict(x) for x in A], C, applytime_legal=True, verbose=False)
        show(r, True)
    print("-" * 92)
    print(f"BAR: recall@FP0 > 0.25 AND > lexical({lex_recall:.3f}), model-free, apply-time legal.")
