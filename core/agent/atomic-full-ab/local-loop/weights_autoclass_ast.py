"""weights_autoclass_ast.py — PURE-STRUCTURE class formation (the rung above lexical-morpheme autoclass).

The honest residual of weights_autoclass.py was: its locus key is lexical (file-basename + name-MORPHEME),
one rung short of name-vocabulary-agnosticism. This module closes that: the class invariant is the AST
NODE-TYPE signature of the edit itself — the grammar of the change (If/Compare/Call/Return/BoolOp/Subscript...),
with ALL identifiers/names/literals DISCARDED. Two edits of the same class share structural shape even when
every function name, variable, and file differ. Pure CPU, Python stdlib `ast` + `tokenize`, no LLM, no Docker.

This is the genuinely name-vocabulary-free rung: where the morpheme version re-discovers a human-shaped name
list, this keys only on the syntactic structure of the mutation — the closest the substrate gets to mechanical
abstraction without a strong model authoring either the vocabulary OR the cluster.
"""

# ───────────────────────────────────────────────────────────────────────────────
# FALSIFIED BY NUMBER (2026-06-23): the pure-structure rung does NOT discriminate.
# Leave-one-out vs 30 random decoys on django compiler.py/sql (K=5) + deletion.py/delete
# (K=3): DISCRIMINATION 0/5 and 0/3 — random non-cluster edits score cosine 0.90-0.98 to
# the prototype, AS HIGH AS true members. Removing all name/vocabulary (token-skeleton OR
# ast node-type histogram) loses the class signal: almost every Python edit shares the same
# grammar (Assign/Attribute/Call/If/Compare/Return), so structure alone is non-discriminative.
# CONCLUSION: the class identity lives in the LOCUS (file-basename + name-MORPHEME), which is
# what weights_autoclass.py (precision 1.0, 5/500) uses. The "lexical residual" is NOT a defect
# to eliminate — it is the LOAD-BEARING signal. The morpheme+file autoclass is the RIGHT
# mechanical (no-model-label) representation; going "more name-agnostic" is falsified.
# Kept as recorded negative evidence (the ladder moves by falsification, not by hope).
# ───────────────────────────────────────────────────────────────────────────────
import ast
import io
import re
import tokenize
from collections import Counter


def _added_lines(diff):
    """The '+' lines of a unified diff (the code the fix introduces), dedented, per file."""
    out = []
    cur = None
    for l in diff.splitlines():
        if l.startswith("diff --git "):
            mf = re.search(r" b/(.+)$", l)
            cur = mf.group(1) if mf else None
        elif l.startswith("+") and not l.startswith("+++") and cur and cur.endswith(".py"):
            out.append(l[1:])
    return out


def edit_ast_signature(diff):
    """Name-vocabulary-FREE structural signature of an edit: the multiset of AST node TYPES in the added code,
    plus (fallback) keyword/operator token types for fragments that don't parse standalone. Identifiers, attribute
    names, and literal values are NEVER included — only the grammar."""
    added = _added_lines(diff)
    sig = Counter()
    if not added:
        return sig
    # Parse the added code; collect ast node-TYPE names (structure only — identifiers/literals discarded).
    import textwrap
    src = textwrap.dedent("\n".join(added))
    for attempt in (src, "if True:\n" + "\n".join("    " + x for x in src.splitlines())):
        try:
            tree = ast.parse(attempt)
            for node in ast.walk(tree):
                n = type(node).__name__
                if n not in ("Name", "Load", "Store", "Constant", "alias", "arg", "Module"):
                    sig[n] += 1
            if sig:
                return sig  # parsed: structural node-type signature is authoritative
        except SyntaxError:
            continue
    # fallback: token-type skeleton (keyword + operator only — name-free)
    try:
        for tok in tokenize.generate_tokens(io.StringIO("\n".join(added)).readline):
            if tok.type == tokenize.NAME and tok.string in (
                    "if", "for", "while", "return", "and", "or", "not", "in", "is", "def", "class",
                    "try", "except", "with", "elif", "else", "lambda", "yield", "raise", "assert"):
                sig["kw:" + tok.string] += 1
            elif tok.type == tokenize.OP:
                sig["op:" + tok.string] += 1
    except Exception:
        pass
    return sig


def _cosine(a, b):
    if not a or not b:
        return 0.0
    keys = set(a) | set(b)
    dot = sum(a.get(k, 0) * b.get(k, 0) for k in keys)
    na = sum(v * v for v in a.values()) ** 0.5
    nb = sum(v * v for v in b.values()) ** 0.5
    return dot / (na * nb) if na and nb else 0.0


def autoclass_ast(resolutions, tau=0.6):
    """resolutions: [{id, diff}]. Cluster by AST-signature cosine similarity >= tau (NO names, NO file, NO model
    label — pure edit grammar). Union-find. Returns clusters with the averaged prototype signature."""
    sigs = {r["id"]: edit_ast_signature(r["diff"]) for r in resolutions}
    ids = [i for i in sigs if sigs[i]]
    parent = {i: i for i in ids}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]; x = parent[x]
        return x

    for i in range(len(ids)):
        for j in range(i + 1, len(ids)):
            if _cosine(sigs[ids[i]], sigs[ids[j]]) >= tau:
                parent[find(ids[i])] = find(ids[j])
    groups = {}
    for i in ids:
        groups.setdefault(find(i), []).append(i)
    clusters = []
    for members in groups.values():
        if len(members) < 2:
            continue
        proto = Counter()
        for m in members:
            proto.update(sigs[m])
        clusters.append({"members": sorted(members), "prototype": dict(proto), "sigs": {m: dict(sigs[m]) for m in members}})
    return clusters


def nearest_prototype(proto, held_sig):
    """Cleanup/recall: structural similarity of a held-out edit to the cluster prototype (0..1)."""
    return _cosine(proto, held_sig if isinstance(held_sig, Counter) else Counter(held_sig))
