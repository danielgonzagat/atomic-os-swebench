# G2 SUBSTRATE LEDGER (cross-model held-out lift — the only success metric, §7)

## G2-001 — 2026-06-23 — EXECUTABLE rung, strong-authored, cross-model
- operator: locate_decision_predicate (canonical ACT, weights_sha256=b2958efa4b58d181, canonical_act=true)
- captured_from: v4-pro on pylint-7080 (CROSS-FILE-ROOT-CAUSE)  | abstraction: STRONG-AUTHORED, K=1
- model_B (lifted): deepseek-v4-flash   | held_out_instance: pylint-6528 (non-circular)
- N=8 | base_resolved=4 | weight_resolved=5 | lift=+1
- navigator injected 8/8; surfaced gold-adjacent root `_is_in_ignore_list_re` (operator never saw 6528)
- VERDICT: **NULL / within-noise** (+1/8 not statistically distinguishable from 0 at N=8; CIs overlap).
  Runner auto-label "PROVED" REJECTED as overclaim (anti-facade). Cross-model executable transfer NOT demonstrated.
- companion (same-model v4-pro probe, NOT a G2): base 4/8 -> prose 2/8 -> prose+navigator 6/8 (suggestive, confounded).
- NEXT RUNG (§5): mechanical-abstraction. Precondition (Phase 0, commit 661378f) DONE; blocker = distinct-bug K>=2
  (accumulate gate-ON green on expand_modules family 7080/6528/4661 so autoclass can form a class by STRUCTURE not model label).
