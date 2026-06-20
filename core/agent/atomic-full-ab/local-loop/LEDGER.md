# LOCAL self-vs-self competitive A/B — LEDGER (lives on disk; loop state of record)

**Protocol (user-defined, exact):** define a task → FIRST fire the atomic agent CLI (DeepSeek V4 Pro,
atomic-only) → THEN fire a subagent of my own TUI (Claude Code, native-only) with the SAME task → wait
both → collect+compare ALL data → improve the atomic agent (generalist-only, via atomic_expand_self) →
repeat same task till atomic dominates → escalate difficulty → forever. Runs 100% LOCAL (no Modal).

**Arms:**
- NATIVE = a Claude Code subagent, tools = Read/Edit/Write/Bash/Grep/Glob only (no MCP, no atomic).
- ATOMIC = `local_atomic_agent.py` (DeepSeek V4 Pro brain + 100% atomic hands via atomic-call.mjs).
- Gate (scoring) is identical for both and re-scored by the orchestrator (no self-report trust).

**Honesty caveat (commensurability):** the two arms use DIFFERENT models (Claude vs DeepSeek), per the
user's explicit definition of this A/B. So token/time/diff gaps are MODEL-CONFOUNDED and are NOT claimed
as representation. The loop only acts on the CLEANLY representation-attributable part of a loss (tool
granularity, ceremony, round-trips, coverage) — never fakes a model gap as a representation gap.

---

## Level 1 — Round 1 — Task L01 (tiny-csv RFC-4180 quoting)
- task: `tasks/L01-csv` — make `node --test` 6/6 (4 RFC-4180 quoting cases) without breaking 2 existing.
- snapshot (both arms, identical): `6458a4fd76634772bd07746dace96c49c468d54d`
- date: 2026-06-20

| metric | NATIVE | ATOMIC | winner |
|---|---|---|---|
| gate pass | ✅ 6/6 | ✅ 6/6 | TIE |
| diff_lines (smaller=better) | 76 | 97 | native |
| edits applied | 1 | 2 | native |
| total tool-calls | 6 | 12 (outline 3, read 4, test 2, replace 3) | native |
| tokens | 31,412 | 63,721 | native (2.0×, model-confounded) |
| wall | ~28s | 58.8s | native (2.1×, model-confounded) |
| invalid-states prevented on disk | 0 | **1** | **ATOMIC** |
| run_tests calls | 1 | 2 | native |

**Verdict:** correctness PARITY (both solve — a milestone: the atomic arm now SEES code & solves, vs the
Modal runs where it was blind and scored 0). NATIVE dominates efficiency. ATOMIC uniquely prevented an
invalid on-disk state (s4 governed refusal → s5 clean apply) — the proof guarantee, real, in a real run.
Atomic does NOT dominate → no escalation → formalize loss class → close it generally → re-run.

### Open loss CLASSES (generalized, representation-attributable)
- **CLASS-R1-A — no batch structural read.** atomic_outline / atomic_read are single-target, so
  understanding an N-file change costs ≥2N round-trips (the atomic arm spent 6 calls — 3 outline + 3
  full-read — to load 3 tiny files; native read broadly in ~2). Generalist (any lang, any multi-file
  task). Clean representation signal (a perfect model still pays N calls if the tool takes 1 file).
  **Fix direction (generalist, via atomic_expand_self):** a macro-operator that outlines+reads a SET of
  files / a glob / a directory in ONE atomic call, returning structure+code together — fewer round-trips,
  less ceremony, same proof. (Absorbs the native "broad read" advantage as a macro-atomic op.)
- CLASS-R1-B (minor) — premature run_tests on empty tree wasted a step (s3). Already steered by the
  empty-diff short-circuit; mild, model-side. Watch, don't fix yet.

### Model-confounded (recorded, NOT acted on as representation)
- tokens 2.0× and wall 2.1× — DeepSeek reasoning verbosity vs Claude. Honest ceiling of a cross-model
  A/B. Will shrink partly when CLASS-R1-A cuts round-trips; the residual is the model, reported as such.

---

## Next exact step
Close CLASS-R1-A via `atomic_expand_self` (generalist batch/glob structural read macro-operator),
validate (all gates green, no false-green, no bypass), then RE-RUN R1/L01 (fresh worktrees) and compare:
target = atomic's read round-trips ≤ native's, with correctness still 6/6 and invalid-states still 0.
If atomic then ties/leads on round-trips (model residual aside) for ≥2 consecutive rounds → escalate to
L02 (bigger multi-file). If not → next class. Write real state here each session.
