# Structural-trava generalization — by-number findings (2026-06-24)

**Directive tested (user, this turn):** my prior "trava needs an embedding model for semantic generalization"
was WRONG; encode the failure by its **structural/causal signature** (typed roles from the verified world —
AST, symbol graph, causal stack, test verdict — identifiers stripped), **model-free**. Bar: **beat 1/4 (0.25)
without any model**, and beat the char-trigram lexical baseline.

**What I built (all model-free, deterministic, CPU, no LLM, no embedding):** `trava_harness.py` (vectorized
eval), `sweep.py` (11 structural signatures), `relabel_exp.py` (official-label robustness), `clean_diag.py`
(confound-free separation). Metric = leave-one-BUG-out **recall@FP0** (held-out FAILED moves blocked by a
cross-bug trava bank at the threshold where blocking any held-out CORRECT move = 0 → the doctrine's SOUND trava).
Real data: 376 real SWE-bench-Verified repair attempts (24 distinct bugs) + the 93-record disproof-corpus.

## Result: the structural hypothesis is FALSIFIED by number, robustly

| instrument / signature | recall@FP0 | cross-bug separation (failed~failed − failed~correct) |
|---|---|---|
| LEXICAL char-trigram (baseline) | 0.126 (gate_pass labels) / **0.000** (official labels) | −0.026 |
| moveshape (name-agnostic AST op) | 0.014 | −0.026 |
| keywords / operators / taxonomy / polarity / indent / combined | 0.000–0.013 | ≈0 or negative |
| ast_nodetype_hist | 0.000 | +0.027 |
| tb_relation (edit vs traceback, the user's literal predicate) | 0.000 | +0.511 **(degenerate: 321/376 = NO_TRACEBACK collapse to one vector)** |
| edit_vs_gold **(POST-HOC oracle, knows gold causal file)** | 0.000 | +0.053 |

**11 diverse model-free structural signatures + lexical + a post-hoc oracle: NONE reaches recall@FP0 > 0.25.**
With official SWE-bench labels (65 correct + 152 failed, 7 bugs with both classes), even lexical drops to 0.000.

## Why (the precise, characterized wall)

1. **352/372 failed attempts already edit the GOLD causal file.** The failure is almost never "wrong place"
   (the user's literal "edited symptom not cause" = only 10/376 = 2.7%, on 5 bugs). It is **right place, wrong
   fix-content**.
2. **Cross-bug, failed moves do NOT form a separable class** from correct moves (separation ≈ 0 / negative for
   every non-degenerate signature, incl. the gold-aware oracle). The discriminating signal — *is this specific
   change correct* — is **semantic fix-content**: the identical AST move-shape ("add an `if`-guard returning X")
   is correct or incorrect depending on the exact condition/value, which abstraction necessarily discards.
3. The one model-free signal that IS real and structural — **edit LOCATION** — is the one operators already
   deliver and that is already mostly correct. There is no structural residue left to exploit.

## The constructive decomposition of the §5 convergence-by-elimination law

| | same-bug failed~failed | cross-bug failed~failed | verdict |
|---|---|---|---|
| LEXICAL | **0.853** | 0.560 (≤ failed~correct) | — |
| STRUCTURAL | **0.658** | 0.275 (≤ failed~correct) | — |

- **WEAK form — WORKS model-free:** on re-fire of the SAME task, models churn *highly similar* wrong moves
  (same-bug failed~failed = 0.85 lex / 0.66 struct). Blocking the proven-wrong move (near-exact match) forces
  exploration → the space shrinks → convergence-by-elimination has real purchase **within a task**. No semantic
  generalization needed — just exact/near-exact memory of the proven-wrong diff.
- **STRONG form — NULL model-free:** cross-task **generalized** travas (one bug's wrong-move class blocking a
  different bug's analogous wrong move → the "margem cresce com o acúmulo" Elevation) have **no model-free
  structural substrate**: cross-bug, a wrong move is no more like another wrong move than like a correct one.

## The honest frontier (a signal that requires a human decision)

The missing signal is **semantic fix-content correctness**, which the doctrine **forbids** capturing via
embedding / model / LLM-judge. So the strong-form Elevation and the no-model rule are in **direct conflict on the
dominant failure mode** — not from fatigue, but proven after exhausting the structure (11 signatures, 2
instruments, official relabel, post-hoc oracle). This is the doctrine's own sanctioned endpoint ("esgotada a
estrutura que já se tem → fronteira honesta"), reached by number — with the twist that the residue is not a
"minor posterior case" but the **dominant** failure mode.

**Decision for the human:** either (a) accept **within-task elimination** (weak form, model-free, real) as the
achievable trava scope, or (b) relax the no-model rule for the **semantic-content layer only** (the thing the
substrate exists to avoid), or (c) relax the **sound-trava 0-FP law** to a small FP budget. The experiment cannot
choose this; it only localizes the wall exactly.

---

## Adversarial confirmation (independent 12-agent workflow, 2026-06-24)

An independent workflow tried to BREAK this null from 8 fresh angles + 2 attacks (every number via the same
harness, full leak audits). **The null held and strengthened.** Highlights:

- **8 new model-free structural break-attempts** (def-use dataflow, AST tree-edit/Zhang-Shasha node-type bag,
  edit↔failing-test relation, TF-IDF/rarity weighting, ordered op-sequence VSA, call-graph locus role,
  weights_autoclass on failures, 7 "untried" textures): **all FAIL.** Best full-pool = 0.083 < lexical 0.126 < 0.25.
- **Label defect found + boundary reinforced:** the `gate_pass` field is unreliable — joining via the official
  score logs (`score_*.log` ↔ `pred_*.jsonl` model_patch, byte-exact) shows **96/376 harness-"failed" attempts
  are officially RESOLVED** (true correct-set ≥120, not 24; 0 reverse flips). Under correct labels lexical
  recall **0.126 → 0.000** and separation goes MORE negative: **correct moves resemble the cross-bug failed bank
  MORE than failed moves do** (held-out correct median sim 0.93 vs failed 0.77). The failed~failed > failed~correct
  hypothesis is falsified harder.
- **Even a label-AWARE oracle reweighting gets recall 0 at FP0** — because name-agnostic abstraction makes some
  correct move *vector-identical* (sim=1.0) to a cross-bug failed move; no reweighting separates identical vectors.
  The discriminative signal is destroyed by abstraction BEFORE any learning can act. (This rules out the
  "just needs a supervised finetuned weight layer" escape: the doctrine's conexionist layer cannot help when the
  inputs collide.)
- **The wall IS soundness:** relax FP0 → **FP=2: lexical 0.259, FP=3: 0.276.** The entire null is 2-3 specific
  correct-move collisions (e.g. a real sympy +19-line fix vs a real sympy +2/−2 failed edit both at char-trigram
  0.999 because they share library boilerplate `from .expr import Expr`). A trava with a tiny FP budget weakly
  generalizes; a SOUND (0-FP) cross-bug trava does not exist model-free.
- The one slice-pass (nameaware_idents 0.29 on 5 traceback bugs) was self-rejected by its own agent; full-pool 0.069.

**Synthesis verdict (independent): NULL, boundary_holds=true.** "Recurring model-free structure is LOCATION
(already mostly right); right-vs-wrong lives in semantic fix-CONTENT with no name-agnostic structural signature."

## The deepest reading (why this is a boundary, not a missing trick)

The thing that actually separates a correct fix from an incorrect one is *"does it pass the battery"* — which
atomic ALREADY computes, **post-hoc, by running the proof (the byte-law §1).** A pre-emptive trava tries to
predict that verdict *cheaply, from structure, before disk.* The data says the cheap structural proxy does not
exist: correct and failed repairs at the same locus collide structurally. So the substrate's proven, model-free
value is exactly: **byte-law (cannot materialize invalid code) + operators (WHERE) + within-task exact-repeat
elimination (WEAK §5).** The **cross-bug semantic-content generalization** the Elevation thesis needs is precisely
what only the byte-law (post-hoc, by running tests) or a model (forbidden) can supply — there is no model-free
shortcut. Reached by number across 19 signatures, 2 instruments, official relabel, post-hoc + supervised oracles.

### Not yet evaluated (need structures the harness does not expose — honest open edges, NOT claimed as null)
(a) preservation-matrix deltas of the edit vs the **pre-edit file body**; (b) AST def-use over the **surrounding
file body** (not just the diff); (c) disproof-corpus verdict-cascade joined to SWE attempts. (a)/(b) need a repo
snapshot; (c) joins a different failure universe (atomic self-evolution vs SWE repair). Mechanism predicts they
hit the same locus-collision wall, but they were not run — so no number is claimed for them.

## The §5 WEAK form has measurable value (offline, model-free, by number)

Per-bug, in temporal order, over the officially-labeled attempts: **55.8% (121/217) of all repair attempts are
near-exact repeats (lexical sim ≥ 0.95) of an EARLIER attempt** — wasted churn that exact-repeat elimination
(no semantics, no model, no driver-side generalization) would skip. In the HARD cases this would measurably
accelerate reaching the fix: **pylint-4661 first resolves only at attempt #70, with 23 wasted near-dup retries
before it**; django-11490 resolves at #9 with 8 wasted before; sympy-13877 at #3 with 1. In **3/9** bugs that have
a resolved attempt, exact-elimination would have skipped wasted retries before the resolution.

**HONEST SCOPE:** this is a **budget/efficiency** gain on a SINGLE task (converge to the known-reachable fix with
fewer wasted attempts), NOT the cross-task Elevation the condition demands: (1) it helps any model equally
(frontier too) → no differential student≥frontier gap; (2) the model EVENTUALLY found the fix without elimination
(pylint-4661 @ #70) → elimination saves attempts, it does not visibly unlock a resolution the model could not
otherwise reach. **Whether elimination lifts RESOLUTION (not just speed) requires the LIVE re-fire loop.**

## The live harness is BUILT and VALIDATED up to the model boundary (`refire_elimination.py`)

The live within-task elimination experiment is now implemented and ready: it runs DeepSeek V4 Pro (the required
fixed student) on each task, accumulating proven-WRONG diffs and injecting them as a **soft prompt-level trava**
purely through the driver's EXISTING `--task <PROBLEM.md>` interface — **so it edits ZERO co-owned files**
(blocker (ii) above is RESOLVED: no `local_atomic_agent.py` edit needed). It is NON-CIRCULAR (the gold/correct diff
is never shown — only wrong moves to avoid) and scored by the OFFICIAL SWE-bench Docker harness. The by-number
question it answers, apples-to-apples: does **sequential re-fire WITH elimination** resolve MORE than
**best-of-K independent one-shots** (same budget)? If yes → the substrate's weak-form makes the fixed model surpass
its own one-shot baseline, by number.

**Scoring plumbing VALIDATED by control (Docker, this session):** gold patch for `pytest-dev__pytest-7982` →
`resolved=1`; empty diff → `resolved=0` ⇒ `PLUMBING_OK=True`. (Gotcha found & encoded: the `requests` suite hits
live network → false negatives in sandboxed Docker; the harness ships a curated NETWORK-FREE `RECOMMENDED_TASKS`.)

**The ONLY remaining blocker is the DeepSeek key.** `DEEPSEEK_API_KEY` is unset (the shared key was correctly
rotated). Without a model you cannot generate new attempts, so a live "surpass baseline" number is impossible to
produce offline — no analysis of existing attempts yields a NEW resolution. Provide a valid key with balance and:
`DEEPSEEK_API_KEY=… DEEPSEEK_MODEL=deepseek-v4-pro python3 refire_elimination.py --k 6` runs it and prints the
DELTA (elimination − baseline) by number. Until then the harness exits cleanly with an honest BLOCKED message.
