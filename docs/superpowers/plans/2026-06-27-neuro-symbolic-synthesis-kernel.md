# Neuro-Symbolic Synthesis Kernel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a live Atomic synthesis kernel that represents SyGuS/CVC5 problems, routes them through CVC5, Z3, and heuristic backends, emits deterministic proof receipts, and exposes the result through the Atomic MCP without weakening `atomic_self_evolution` or `atomic_expand_self` boundaries.

**Architecture:** Consolidate the current partial meta-synthesis files into one receipt-centered kernel. Formal backends can emit `PROVEN`, `UNSAT`, `UNKNOWN`, `ABSENT`, or `INVALID`; heuristic paths can emit only `HEURISTIC_UNPROVEN`. The MCP surface returns receipts and candidates but never writes engine files or promotes unproven candidates.

**Tech Stack:** TypeScript ES modules, Node.js `crypto`/`child_process`, existing Z3 Python cover solver, existing Vitest runner, Atomic MCP `atomic_dispatch_tool` for fresh-runtime smoke tests.

---

## File Structure

- Create: `core/atomic-edit/engine-synthesis-kernel.ts` for canonical JSON, `sha256`, `SynthesisProblem`, `Candidate`, `BackendAttempt`, `ProofReceipt`, receipt verification, promotion eligibility, and backend ladder orchestration.
- Modify: `core/atomic-edit/engine-cvc5-sygus.ts` so CVC5 detection and execution emit kernel verdicts with path/version/search evidence.
- Modify: `core/atomic-edit/engine-sygus.ts` so SyGuS rendering remains stable and receipt-friendly.
- Modify: `core/atomic-edit/engine-theory-ladder.ts` so ladder steps are derived from kernel attempts and never treat heuristic output as formal proof.
- Modify: `core/atomic-edit/engine-meta-synth.ts` so the partial island synthesizer emits canonical receipts and refuses heuristic promotion.
- Modify: `core/atomic-edit/z3-constraint-finder.mjs` only if the Z3 adapter needs a stable wrapper while preserving current CLI behavior.
- Modify: `core/atomic-edit/server-tools-meta-synth.ts` so `atomic_meta_synth` returns kernel receipts and proof limits.
- Create: `core/atomic-edit/engine-synthesis-kernel.test.ts` for receipt hashing, forged receipt rejection, CVC5 absence, heuristic non-authority, Z3 fixture, and no direct writes.
- Create: `core/atomic-edit/gates/meta-synth-engine.proof.mjs` for black-box honesty proof.

---

### Task 1: Kernel Contracts And Receipt Hashes

**Files:**
- Create: `core/atomic-edit/engine-synthesis-kernel.ts`
- Test: `core/atomic-edit/engine-synthesis-kernel.test.ts`

- [ ] **Step 1: Write failing receipt hash tests**

Create a `SynthesisProblem` fixture with `kind: 'rewrite'`, `domain: 'ast-rewrite'`, one string variable, one example constraint, objective `synthesize`, and only the `heuristic` backend. Assert that `canonicalJson({ b: 2, a: 1 })` is exactly `{"a":1,"b":2}`, `hashSynthesisProblem(problem)` is a 64-character lowercase hex string, a `HEURISTIC_UNPROVEN` receipt verifies, a forged receipt hash fails verification, and `promotionEligible(receipt)` is false.

- [ ] **Step 2: Run the test and confirm it fails**

Run: `cd core/atomic-edit && npm test -- engine-synthesis-kernel.test.ts`
Expected: FAIL because `engine-synthesis-kernel.js` does not exist.

- [ ] **Step 3: Implement the minimal kernel contracts**

Create `engine-synthesis-kernel.ts` with these exports: `SynthesisVerdict`, `SynthesisBackend`, `SynthesisProblem`, `Candidate`, `BackendAttempt`, `ProofReceipt`, `canonicalJson`, `sha256`, `hashSynthesisProblem`, `hashCandidate`, `makeProofReceipt`, `verifyProofReceipt`, and `promotionEligible`. `makeProofReceipt` computes `problemSha256`, candidate hashes, and `receiptSha256`; `verifyProofReceipt` recomputes the canonical hash with `receiptSha256` removed; `promotionEligible` returns true only for a valid `PROVEN` receipt with `authority: 'formal'`.

- [ ] **Step 4: Run the test and confirm it passes**

Run: `cd core/atomic-edit && npm test -- engine-synthesis-kernel.test.ts`
Expected: PASS for canonical hash and forged receipt rejection.

---

### Task 2: CVC5 SyGuS Adapter With Honest Absence

**Files:**
- Modify: `core/atomic-edit/engine-cvc5-sygus.ts`
- Modify: `core/atomic-edit/engine-sygus.ts`
- Test: `core/atomic-edit/engine-synthesis-kernel.test.ts`

- [ ] **Step 1: Add failing CVC5 absence and SyGuS representation tests**

Assert `detectCvc5({ env: { PATH: '' }, candidatePaths: [] })` returns `verdict: 'ABSENT'`, `evidence.checked` as an empty list, and an evidence reason mentioning `cvc5`. Assert `buildStringReplaceSyGuS` for a `colour` to `color` example emits a program containing `(check-synth)` and `str.replace`.

- [ ] **Step 2: Run the CVC5 tests and confirm they fail**

Run: `cd core/atomic-edit && npm test -- engine-synthesis-kernel.test.ts -t CVC5`
Expected: FAIL because the old adapter exports `available/unavailable/skipped/error`, not kernel verdicts.

- [ ] **Step 3: Implement `detectCvc5` and update `runCvc5SyGuS`**

`detectCvc5` checks explicit `cvc5Bin`, `CVC5_BIN`, each PATH segment, and known Homebrew paths. It records every checked executable path. Missing binary returns `ABSENT`. A reachable binary runs `--version` and returns `UNKNOWN` with version evidence until a SyGuS solve is actually run. `runCvc5SyGuS` maps a successful solve with solver output to `PROVEN` only for the rendered problem and maps timeout/nonzero/unparseable output to `UNKNOWN` or `INVALID`.

- [ ] **Step 4: Run the CVC5-focused tests**

Run: `cd core/atomic-edit && npm test -- engine-synthesis-kernel.test.ts -t CVC5`
Expected: PASS with `ABSENT` in a sandbox where no solver path is visible, or non-ABSENT evidence when `CVC5_BIN` points to a runnable solver.

---

### Task 3: Backend Ladder For Z3 And Heuristic Non-Authority

**Files:**
- Modify: `core/atomic-edit/engine-synthesis-kernel.ts`
- Modify: `core/atomic-edit/engine-meta-synth.ts`
- Modify: `core/atomic-edit/engine-theory-ladder.ts`
- Modify: `core/atomic-edit/z3-constraint-finder.mjs`
- Test: `core/atomic-edit/engine-synthesis-kernel.test.ts`

- [ ] **Step 1: Add failing backend ladder tests**

Add one test where a `rewrite` problem with the `heuristic` backend returns a receipt whose verdict is `HEURISTIC_UNPROVEN` and `promotionEligible` is false. Add one test where a `cover` problem with a single `A -> B` coupling and the `z3` backend returns either `PROVEN` with formal authority or `ABSENT` with solver evidence.

- [ ] **Step 2: Run backend tests and confirm they fail**

Run: `cd core/atomic-edit && npm test -- engine-synthesis-kernel.test.ts -t "heuristic|Z3"`
Expected: FAIL because `runSynthesisKernel` is missing or Z3 is not wrapped yet.

- [ ] **Step 3: Implement `runSynthesisKernel`**

Implement deterministic backend ordering from `limits.backends`. For `z3`, translate `bool-cover` constraints into the existing coupling cover solver and emit `PROVEN`, `UNSAT`, `UNKNOWN`, or `ABSENT`. For `heuristic`, produce candidate facts only as `HEURISTIC_UNPROVEN`. For `cvc5-sygus`, call `runCvc5SyGuS` and keep missing solver as `ABSENT`.

- [ ] **Step 4: Update meta-synthesis to consume kernel receipts**

`synthesizeMetaOperator` returns `ok`, `problem`, `receipts`, `promotionEligible`, `operator`, `train`, `heldOut`, `sygus`, `cvc5`, and `ladder`. It may include a candidate source in `operator`, but `promotionEligible` is true only when at least one verified formal receipt is `PROVEN`.

- [ ] **Step 5: Run backend ladder tests**

Run: `cd core/atomic-edit && npm test -- engine-synthesis-kernel.test.ts`
Expected: PASS for canonical receipts, CVC5 absence, Z3 fixture, and heuristic non-authority.

---

### Task 4: MCP Surface And Fresh Runtime Smoke

**Files:**
- Modify: `core/atomic-edit/server-tools-meta-synth.ts`
- Modify: `core/atomic-edit/server.ts`
- Test: `core/atomic-edit/engine-synthesis-kernel.test.ts`

- [ ] **Step 1: Add failing MCP shape test**

Assert `synthesizeMetaOperator(undefined, { allowCvc5: false })` returns `problem.problemSha256`, a nonempty `receipts` array, `promotionEligible`, a `proofLimits` array, and no serialized `writeFileSync` text.

- [ ] **Step 2: Run the MCP shape test and confirm it fails or exposes the old shape**

Run: `cd core/atomic-edit && npm test -- engine-synthesis-kernel.test.ts -t MCP-safe`
Expected: FAIL until `engine-meta-synth.ts` and `server-tools-meta-synth.ts` return the kernel result shape.

- [ ] **Step 3: Update `server-tools-meta-synth.ts`**

Expose `atomic_meta_synth` with inputs `name`, `train`, `heldOut`, `allowCvc5`, `cvc5Bin`, and `verifyReceipt`. The handler returns the kernel result and a `proofLimits` array stating no direct writes, no heuristic promotion, and only formal `PROVEN` receipts can be considered by `atomic_self_evolution`.

- [ ] **Step 4: Run TypeScript and fresh MCP smoke**

Run: `cd core/atomic-edit && npx tsc -p tsconfig.json --noEmit`
Expected: PASS.

Run via MCP dispatcher: `atomic_dispatch_tool` with `toolName: atomic_meta_synth` and `args: { allowCvc5: false }`.
Expected: fresh runtime returns receipt data where CVC5 is `ABSENT` or `UNKNOWN`, heuristic is `HEURISTIC_UNPROVEN`, and `promotionEligible` is false unless a formal backend proves the problem.

---

### Task 5: Honesty Gate And Completion Audit

**Files:**
- Create: `core/atomic-edit/gates/meta-synth-engine.proof.mjs`
- Modify: `core/atomic-edit/engine-synthesis-kernel.test.ts`

- [ ] **Step 1: Write the proof gate**

The proof gate runs the default island and checks five facts: the kernel surface exists through `problem.problemSha256`; every receipt verdict is one of `PROVEN`, `UNSAT`, `UNKNOWN`, `ABSENT`, `INVALID`, or `HEURISTIC_UNPROVEN`; the heuristic receipt is non-authoritative; heuristic-only results are not promotion eligible; and the serialized result contains no `writeFileSync` text.

- [ ] **Step 2: Run the proof gate and confirm it passes**

Run: `node core/atomic-edit/gates/meta-synth-engine.proof.mjs --json`
Expected: JSON with `ok: true` and `failures: 0`.

- [ ] **Step 3: Run the full local verification set**

Run: `cd core/atomic-edit && npm test -- engine-synthesis-kernel.test.ts`
Expected: PASS.

Run: `cd core/atomic-edit && npx tsc -p tsconfig.json --noEmit`
Expected: PASS.

Run: `node core/atomic-edit/gates/meta-synth-engine.proof.mjs --json`
Expected: PASS.

- [ ] **Step 4: Completion audit**

Inspect evidence for every acceptance criterion in `docs/superpowers/specs/2026-06-27-neuro-symbolic-synthesis-kernel-design.md`: live kernel surface, SyGuS representation, CVC5 `ABSENT` honesty, Z3 `PROVEN` fixture or `ABSENT` with evidence, heuristic `HEURISTIC_UNPROVEN`, promotion refusal, deterministic receipts, scratch/docs honesty gate, no backend direct writes, and compatibility with `atomic_self_evolution` and `atomic_expand_self`.
