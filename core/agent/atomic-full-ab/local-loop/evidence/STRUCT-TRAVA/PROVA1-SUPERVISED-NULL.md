# Prova 1 — supervised net on atomic's own execution labels: held-out NULL (adversarially verified)

**Date:** 2026-06-24. **Question:** does a SMALL SUPERVISED net (numpy logreg/MLP/GBS/kNN), trained on the
atomic's OWN execution labels (official SWE-bench resolved/unresolved), SEPARATE correct-vs-failed repair
MOVES *held-out* at the sound-trava constraint (recall@FP0 > 0.25, leave-one-BUG-out)? This is the empirical
gate the "fix-content net" Elevation thesis depended on.

## Corpus (official labels, leakage-audited)
- Built by `prova1_supervised.py:build_official()` — byte-exact join of `evidence/**/score_*.log`
  (`Instances resolved: N`) to its sibling `pred_*.jsonl` `model_patch`, `y=1 == FAILED`.
- **166 moves / 58 correct / 108 failed / 12 bugs (7 with both classes).**
- Leakage audit (adversarial): 0 byte-exact duplicate diffs, 0 cross-bug lex-cosine>0.97 near-dups,
  leave-one-BUG-out shares 0 bugs across train/test. Clean.

## Result — NULL HOLDS at the bar (recall@FP0 > 0.25 AND > lexical), by number
| feature space | in-sample recall@FP0 | held-out (LOO-bug) recall@FP0 |
|---|---|---|
| lexical char-trigram | 1.000 | **0.000** |
| def-use roles | 0.880 | **0.009** |
| AST ins/del | 0.120 | **0.046** |
| fused lex+du+ast | 1.000 | **0.000** |

- Held-out fused by FP budget: FP0=0.000 FP1=0.000 FP2=0.000 FP3=0.000 FP5=0.556.
- Permuted-label control (held-out): 0.018 / 0.000 / 0.046 — **real held-out is indistinguishable from chance**
  in the lex/du/ast space.
- Learning curve (held-out FP0 vs #train bugs): 0.039 → 0.019 → 0.065 → 0.002 — **flat, no accumulation.**
- The signal EXISTS in-sample (1.0 memorization, reproduces the ~0.85 "oracle ceiling") but does NOT generalize
  cross-bug: every model class memorizes in-sample and collapses held-out. Raising capacity (MLP H 4→32, boosting
  40→160 rounds) raised only in-sample → **bottleneck is generalization, not capacity.**

## Adversarial verification (independent 5-agent workflow, all numbers re-run)
4 attack angles each tried to BREAK the null; none cleared the bar (`any_pass=0`, `verdict=NULL_HOLDS`):
- **capacity** (MLP/GBS/kNN/L1-L2 sweep): best honest held-out FP0 = 0.093; held-out = permuted chance. NULL.
- **leakage/pipeline audit**: fixing hash collisions (D up to 262144, explicit vocab, TF-IDF) leaves held-out
  FP0 = exactly 0.000; global-FP0 threshold not a single poison point (≥4 inseparable correct moves). NULL,
  reported null is leakage-clean.
- **metric fairness** (per-fold-sound FP0, ROC/PR-AUC, abstain): most-generous sound relaxation = 0.0476 held-out,
  killed by permuted control; weak pooled ROC-AUC 0.752 is lexical-driven and per-bug < chance (0.389); reaching
  recall 0.25 needs a real FP budget of 4 blocked correct (6.9%) = fork-c, not sound. NULL.
- **richer model-free features** (op/keyword n-grams + typed-role proxies + diff-shape + edit↔issue overlap from
  problem_statement, never gold): best HONEST held-out FP0 = **0.167** (L2 logreg l2=1.0, nested-CV 0.111). The
  single 0.269 point is an ARTIFACT (l2 tuned against the held-out pool, iteration-fragile 0.093@200it, collapses
  under bug-shuffle). NULL at the bar.

## Honest refinement (the wall is FINITE, not literally zero)
The original lex/du/ast number is ≈chance. BUT with **richer apply-time-legal model-free features** there is
**real above-chance sound held-out signal ≈ 0.167** (permuted control ≤0.056, bug-shuffle ≤0.037, stable across
100→800 optimizer iters, above the lexical control's 0.000). It simply does **not reach 0.25**. So:
- The fix-content net does **not** clear the sound cross-bug bar → it is **not** the Elevation mechanism. (Pivot stands.)
- But "informação ausente / exatamente zero" is too strong: the sound cross-bug ceiling for model-free features is
  ~0.167, a finite wall.
- **Most important caveat:** the corpus is tiny (12 bugs, 7 both-class, 58/108 moves); LOO folds are small enough
  that the 0.167-vs-0.25 gap sits inside the noise. **Underpowered.**

## Recommended decision (by the synthesis judge)
Primary: **collect a larger labeled corpus** — only more bugs resolve whether richer apply-time-legal features
cross 0.25 honestly. Secondary: **relax 0-FP to a small FP budget** (fork-c, ~5% FP / FP3) already yields ~0.5
recall if the use-case tolerates blocking a few correct moves.

## Reproduce
- `prova1_supervised.py` (this dir) — `build_official`, feature extractors, `fit_logreg`, `loo_bug_scores`,
  `recall_at_fp`. Run: `python3 prova1_supervised.py`.
- Adversarial scripts (scratchpad): `prova1_capacity.py`, `prova1_leakage_audit.py`, `prova1_richfeat.py`,
  `prova1_metric_fairness.py`, `prova1_nestedcv_fast.py`, `prova1_strongest_legit.py`.

**Net:** the supervised fix-content escape is **falsified at the sound 0.25 bar** (adversarially verified, NULL),
with the honest nuance that the model-free cross-bug ceiling is a finite ~0.167 (above chance, below bar) on an
underpowered 12-bug corpus. Direction → amplify PROCESS (guards, within-task elimination, navigation, byte-law),
measure Elevation by number. See `ATOMIC-DIRETIVA-ELEVACAO-POR-PROCESSO.md`.
