#!/usr/bin/env bash
set -euo pipefail

HERE="/Users/danielpenin/atomic-os-swebench/core/agent/atomic-full-ab/local-loop"
cd "$HERE"

python3 - <<'PY'
import json
import pathlib
import tempfile

import local_atomic_agent as agent
import weights_admit as w

wrong_a = {
    "event": "candidate_edit_rejected",
    "edit_target": "requests/sessions.py:merge_setting",
    "symptom_loci": ["requests/sessions.py:merge_setting"],
    "causal_loci": ["requests/models.py:prepare_headers"],
    "test_verdict": "fail",
    "byte_class": "byte_negative",
    "ast": [{"role": "edited_node", "kind": "FunctionDef"}],
    "surface_words_ignored": "patched the visible None header cleanup site",
}
wrong_b = {
    "event": "candidate_edit_rejected",
    "edit_target": "pylint/config/__init__.py:cache_dir",
    "symptom_loci": ["pylint/config/__init__.py:cache_dir"],
    "causal_loci": ["pylint/lint/run.py:resolve_cache_backend"],
    "test_verdict": "fail",
    "byte_class": "byte_negative",
    "ast": [{"role": "edited_node", "kind": "FunctionDef"}],
    "surface_words_ignored": "modified the call-site where the error appeared",
}
correct = {
    "event": "candidate_edit_candidate",
    "edit_target": "pylint/lint/run.py:resolve_cache_backend",
    "symptom_loci": ["pylint/config/__init__.py:cache_dir"],
    "causal_loci": ["pylint/lint/run.py:resolve_cache_backend"],
    "test_verdict": "candidate",
    "byte_class": "byte_candidate",
    "ast": [{"role": "edited_node", "kind": "FunctionDef"}],
}

sig_a = w.structural_signature_from_event(wrong_a)
sig_b = w.structural_signature_from_event(wrong_b)
sig_correct = w.structural_signature_from_event(correct)

assert sig_a == sig_b, (sig_a, sig_b)
assert sig_a["edit_target_role"] == "symptom_not_causal"
assert sig_correct["edit_target_role"] == "causal_not_symptom"

stack_wrong_a = {
    "event": "candidate_edit_rejected",
    "edit_target": "repo_a/views.py:visible_handler",
    "symptom_loci": ["repo_a/views.py:visible_handler"],
    "causal_loci": ["repo_a/policy.py:root_rule"],
    "failing_stack_loci": ["repo_a/tests/test_views.py:test_visible", "repo_a/views.py:visible_handler"],
    "test_loci": ["repo_a/tests/test_views.py:test_visible"],
    "symbol_graph_edges": [
        {"source": "repo_a/views.py:visible_handler", "target": "repo_a/policy.py:root_rule", "kind": "caller"}
    ],
    "preservation_matrix": {"ast": True, "symbols": True, "behavior": False, "repo_a/views.py": "changed"},
    "surface_words_ignored": "changed the view that was on the traceback",
}
stack_wrong_b = {
    "event": "candidate_edit_rejected",
    "edit_target": "pkg/api.py:route",
    "symptom_loci": ["pkg/api.py:route"],
    "causal_loci": ["pkg/rules.py:decision"],
    "failing_stack_loci": ["pkg/tests/test_api.py:test_route", "pkg/api.py:route"],
    "test_loci": ["pkg/tests/test_api.py:test_route"],
    "symbol_graph_edges": [
        {"source": "pkg/api.py:route", "target": "pkg/rules.py:decision", "kind": "caller"}
    ],
    "preservation_matrix": {"ast": True, "symbols": True, "behavior": False, "pkg/api.py": "changed"},
    "surface_words_ignored": "patched the route mentioned by the exception",
}
stack_causal = {
    "event": "candidate_edit_candidate",
    "edit_target": "pkg/rules.py:decision",
    "symptom_loci": ["pkg/api.py:route"],
    "causal_loci": ["pkg/rules.py:decision"],
    "failing_stack_loci": ["pkg/tests/test_api.py:test_route", "pkg/api.py:route"],
    "test_loci": ["pkg/tests/test_api.py:test_route"],
    "symbol_graph_edges": [
        {"source": "pkg/api.py:route", "target": "pkg/rules.py:decision", "kind": "caller"}
    ],
    "preservation_matrix": {"ast": True, "symbols": True, "behavior": True, "pkg/rules.py": "changed"},
}
stack_sig_a = w.structural_signature_from_event(stack_wrong_a)
stack_sig_b = w.structural_signature_from_event(stack_wrong_b)
stack_sig_causal = w.structural_signature_from_event(stack_causal)
assert stack_sig_a == stack_sig_b, (stack_sig_a, stack_sig_b)
assert stack_sig_a["causal_stack.edited_stack_relation.kind"] == "edited_failure_stack_symptom_not_causal"
assert stack_sig_a["causal_stack.edited_test_relation.kind"] == "outside_test_locus"
assert stack_sig_a["symbol_graph.edited_relation.kind"] == "edited_source_to_causal"
assert stack_sig_a["symbol_graph.edge_kind.kind"] == "caller"
assert stack_sig_a["preservation.preserve_behavior.status"] == "violated"
assert stack_sig_a["preservation.preserve_ast.status"] == "preserved"
assert stack_sig_causal["causal_stack.edited_stack_relation.kind"] == "edited_causal_locus"
assert stack_sig_causal["symbol_graph.edited_relation.kind"] == "edited_target_from_symptom"
stack_surface = json.dumps(stack_sig_a, sort_keys=True)
for forbidden in ("repo_a", "pkg", "views.py", "api.py", "policy.py", "rules.py", "visible_handler", "route", "root_rule", "decision", "test_visible", "test_route"):
    assert forbidden not in stack_surface, f"surface token leaked into causal/symbol signature: {forbidden}"

stack_same = w.vsa_similarity(w.encode_vsa_signal(stack_wrong_a), w.encode_vsa_signal(stack_wrong_b))
stack_different = w.vsa_similarity(w.encode_vsa_signal(stack_wrong_a), w.encode_vsa_signal(stack_causal))
assert stack_same > 0.95, stack_same
assert stack_different < 0.75, stack_different

surface = json.dumps(sig_a, sort_keys=True)
for forbidden in ("requests", "pylint", "merge_setting", "cache_dir", "prepare_headers", "resolve_cache_backend", "patched", "modified"):
    assert forbidden not in surface, f"surface token leaked into structural signature: {forbidden}"

same_error = w.vsa_similarity(w.encode_vsa_signal(wrong_a), w.encode_vsa_signal(wrong_b))
different_role = w.vsa_similarity(w.encode_vsa_signal(wrong_a), w.encode_vsa_signal(correct))
assert same_error > 0.95, same_error
assert different_role < 0.70, different_role

trava = w.make_trava(wrong_a, opposite_suggestion="trace to causal locus before editing", threshold=0.90)
blocked, sim_blocked, opposite = w.trava_blocks(trava, wrong_b)
allowed, sim_allowed, _ = w.trava_blocks(trava, correct)
assert blocked, sim_blocked
assert not allowed, sim_allowed
assert opposite

before = sim_blocked
w.trava_reinforce(trava, wrong_b)
_, after, _ = w.trava_blocks(trava, wrong_b)
assert after > before, (before, after)

legacy_a = w.vsa_similarity(w.encode_vsa_text(wrong_a["surface_words_ignored"]), w.encode_vsa_text(wrong_b["surface_words_ignored"]))
assert legacy_a < same_error, (legacy_a, same_error)

with tempfile.TemporaryDirectory() as td:
    root = pathlib.Path(td)
    src = root / "pkg" / "worker.py"
    src.parent.mkdir()
    src.write_text(
        "def compute(value):\n"
        "    if value is None:\n"
        "        return 0\n"
        "    return value + 1\n"
    )
    diff = (
        "diff --git a/pkg/worker.py b/pkg/worker.py\n"
        "--- a/pkg/worker.py\n"
        "+++ b/pkg/worker.py\n"
        "@@ -1,4 +1,4 @@\n"
        " def compute(value):\n"
        "-    if value is None:\n"
        "+    if value == 0:\n"
        "         return 0\n"
        "     return value + 1\n"
    )
    event = agent._structural_learning_event(
        {
            "final_diff": diff,
            "diff_lines": 1,
            "edits_applied": 1,
            "failing_stack_loci": ["tests/test_worker.py:test_compute", "pkg/worker.py:compute"],
            "test_loci": ["tests/test_worker.py:test_compute"],
            "causal_loci": ["pkg/rules.py:policy"],
            "symbol_graph_edges": [
                {"source": "pkg/worker.py:compute", "target": "pkg/rules.py:policy", "kind": "caller"}
            ],
            "preservation_matrix": {"ast": True, "symbols": True, "behavior": False, "pkg/worker.py": "changed"},
        },
        "PROBLEM.md",
        False,
        no_gate=True,
        workdir=str(root),
    )
    encoded = json.dumps(event, sort_keys=True)
    assert "FunctionDef" in encoded
    assert "If" in encoded
    assert "edited_failure_stack_file_not_causal" in encoded
    assert "edited_source_file_to_causal" in encoded
    assert "preserve_behavior" in encoded
    assert "compute" not in encoded
    assert "worker.py" not in encoded
    assert "pkg" not in encoded

print("Structural/causal VSA contract ok", f"same={same_error:.3f}", f"different={different_role:.3f}", f"stack_same={stack_same:.3f}", f"stack_different={stack_different:.3f}", f"legacy={legacy_a:.3f}")
PY

grep -q 'FINETUNE-STRUCTURAL' "$HERE/local_atomic_agent.py"
if grep -q 'FINETUNE-LEXICAL\\|structural_signature import\\|from structural_signature' "$HERE/local_atomic_agent.py"; then
  echo "runtime finetuning must not fall back to lexical or external structural encoders" >&2
  exit 1
fi
