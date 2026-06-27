# Neuro-Symbolic Synthesis Kernel Design

## Status

Approved design. Implementation must not start from this document until the written spec has been reviewed and an implementation plan has been created.

## Current Evidence

The current live worktree shows an existing empirical and formal substrate:

- `core/atomic-edit/hypothesis-generator.mjs` reads the real Atomic corpus and produces candidate couplings.
- `core/atomic-edit/autonomous-evolution.mjs` synthesizes proof-gate source from informative couplings.
- `core/atomic-edit/z3-constraint-finder.mjs` and `formal/atomic-algebra/coupling_cover_z3.py` already use Z3 for a proven minimal cover class.
- `core/atomic-edit/server-tools-self-evolution.ts` exposes `atomic_self_evolution` as the deterministic promotion/receipt/archive verifier.
- `formal/atomic-algebra/NwayConfluence.lean` and related Z3 scripts provide an existing formal proof surface.

The current live search found no integrated SyGuS/CVC5/meta-synthesis/theory-ladder engine surface beyond `cvc5Status: 'pending'` in `core/atomic-edit/gates/h2-harness-contract.proof.mjs`. A runtime probe from the Atomic sandbox found `z3`, `python3`, `lean`, and `lake`, but did not find `cvc5` on the visible PATH or common Homebrew paths. The design must therefore support real CVC5 when reachable while treating absence as a first-class, honest state.

## Problem

Atomic already has strong verified editing, corpus mining, self-evolution admission, Z3/Lean formal proofs, and MCP-controlled mutation. The missing step for the Atomic 10/10 direction is a living neuro-symbolic synthesis kernel that turns empirical hypotheses into formally classified candidates without pretending that a missing solver is a successful proof.

The current gap is not simply "install cvc5". The gap is architectural: there is no shared kernel that represents synthesis problems, routes them through formal and heuristic backends, emits deterministic proof receipts, and feeds the existing self-evolution boundary without giving heuristic output authority.

## Goals

1. Add a first-class neuro-symbolic synthesis surface inside the Atomic engine.
2. Represent SyGuS/CVC5 synthesis problems even when CVC5 is absent from the active runtime.
3. Reuse Z3 as an existing formal backend instead of leaving it as a side script.
4. Keep heuristic generation useful but explicitly non-authoritative.
5. Emit deterministic, hashable, re-executable receipts for every backend attempt.
6. Preserve the existing promotion boundary: only `atomic_self_evolution` decides promotion and only `atomic_expand_self` writes core changes.
7. Add honesty gates that fail if SyGuS/CVC5 exists only in scratch/docs or if absence is reported as success.

## Non-Goals

- Do not install CVC5 as part of this first slice.
- Do not claim whole-host Y completion.
- Do not auto-promote new operators from heuristic candidates.
- Do not rewrite the entire self-evolution pipeline.
- Do not let any backend write directly into `core/atomic-edit/**`.
- Do not declare Atomic 10/10 complete from this slice alone.

## Architecture

The first slice introduces a kernel with this flow:

```text
corpus/failure
  -> hypothesis-generator
  -> SynthesisProblem
  -> BackendLadder(cvc5-sygus, z3, heuristic)
  -> Candidate
  -> Verifier
  -> ProofReceipt
  -> atomic_self_evolution
  -> atomic_expand_self only after promotion
```

The kernel sits between empirical hypothesis generation and self-evolution admission. It does not replace either side.

## Core Concepts

### SynthesisProblem

A `SynthesisProblem` is the canonical, backend-independent unit of synthesis. It must be JSON-serializable and hashable.

Fields:

- `kind`: `cover`, `rewrite`, `invariant`, `operator`, or `gate`.
- `intent`: human or agent intent in a compact stable form.
- `source`: corpus records, gate names, files, symbols, and receipt hashes that generated the problem.
- `domain`: theory or language fragment such as `lia`, `bool-cover`, `ast-rewrite`, or `gate-coupling`.
- `variables`: typed symbolic variables.
- `constraints`: backend-independent constraints.
- `objective`: minimize, satisfy, synthesize, prove, or classify.
- `limits`: timeout, max candidates, grammar depth, and admitted backend set.
- `problemSha256`: canonical hash over all semantic fields.

### BackendAttempt

A `BackendAttempt` records one backend's execution against one `SynthesisProblem`.

Backends for the first slice:

- `cvc5-sygus`: Detects CVC5 and prepares SyGuS-LIA/Bool problems. If unavailable, returns `ABSENT` with command/path evidence.
- `z3`: Reuses the existing Z3 cover proof class and returns `PROVEN`, `UNSAT`, `UNKNOWN`, or `ABSENT`.
- `heuristic`: Produces candidates from existing corpus/hypothesis logic but returns `HEURISTIC_UNPROVEN`, never `PROVEN`.

### Candidate

A `Candidate` is an output proposed by a backend. It is not automatically trusted.

Fields:

- `candidateSha256`
- `problemSha256`
- `backend`
- `payload`
- `renderedArtifact`, optional source for a future gate/operator
- `limits`
- `authority`: `formal`, `heuristic`, or `none`

### ProofReceipt

A `ProofReceipt` is the authority boundary for the kernel.

Allowed verdicts:

- `PROVEN`: backend proved or formally verified the candidate for the declared domain.
- `UNSAT`: backend proved no candidate exists within the declared domain.
- `UNKNOWN`: backend ran but could not decide.
- `ABSENT`: backend/toolchain was not reachable in the current runtime.
- `INVALID`: candidate failed independent verification.
- `HEURISTIC_UNPROVEN`: candidate may be useful, but has no formal authority.

Only `PROVEN` may enter automatic promotion consideration. Every other status can feed memory, curriculum, or investigation queues, but must not become a promoted gate/operator without additional proof.

## Integration Points

### hypothesis-generator

`hypothesis-generator` remains the empirical source. It should gain a builder that converts informative couplings into `SynthesisProblem` records rather than only returning informal candidate descriptions.

### autonomous-evolution

`autonomous-evolution` should stop treating a mined coupling as sufficient authority for gate synthesis. It should request a `ProofReceipt` from the kernel:

- `PROVEN`: may render a gate candidate for promotion.
- `HEURISTIC_UNPROVEN`: may append to hypothesis ledger only.
- `ABSENT`, `UNKNOWN`, `UNSAT`, `INVALID`: record as honest result and stop.

### z3-constraint-finder

`z3-constraint-finder` becomes a formal backend adapter inside the ladder. Its minimal-cover result should be wrapped in the same `ProofReceipt` structure as future CVC5/SyGuS attempts.

### atomic_self_evolution

`atomic_self_evolution` remains the promotion/admission receipt engine. It should consume candidate facts and proof receipts; it should not become a candidate generator.

### atomic_expand_self

`atomic_expand_self` remains the only way to write engine changes. The synthesis kernel may generate candidate source text, but it must never write it directly to `core/atomic-edit/**`.

### atomic-memory

The first slice should record semantic reasons in memory only after a receipt exists. Memory entries should link intent, problem hash, backend attempts, verdict, source corpus, and any promoted artifact.

## Error Handling

The kernel must treat absence and uncertainty as expected states, not exceptions.

- Missing `cvc5`: `ABSENT` with path search evidence.
- Present CVC5 but unsupported problem: `UNKNOWN` or `INVALID`, depending on failure mode.
- Z3 missing: `ABSENT`, not fallback success.
- Z3 timeout: `UNKNOWN` with timeout evidence.
- Heuristic candidate: `HEURISTIC_UNPROVEN` even when it looks useful.
- Receipt hash mismatch: `INVALID`.
- Candidate verification failure: `INVALID`.

## Gates And Tests

The first implementation plan must include gates that prove these invariants:

1. CVC5 absence is reported as `ABSENT`, not green success.
2. CVC5 presence, when reachable, is detected from actual executable output, not documentation.
3. A small Z3 cover fixture returns `PROVEN` deterministically.
4. A heuristic fixture returns `HEURISTIC_UNPROVEN` and is refused by automatic promotion.
5. Every receipt is canonical and hash-stable.
6. A forged receipt hash is rejected.
7. No backend writes to `core/atomic-edit/**`.
8. The only promotion path for engine changes remains `atomic_expand_self`.
9. SyGuS/CVC5 references in scratch/docs without the kernel surface fail the honesty gate.
10. `autonomous-evolution` distinguishes `PROVEN` from `HEURISTIC_UNPROVEN`.

## Delivery Phases

### Phase 1: Contracts

Add the problem, candidate, backend attempt, and receipt model. Include canonical hash functions and fixtures. This phase can pass without CVC5 installed.

### Phase 2: Backend Ladder

Add CVC5 detection and SyGuS problem rendering, Z3 adapter wrapping the existing minimal-cover proof class, and heuristic adapter wrapping current corpus-derived candidate behavior.

### Phase 3: Loop Integration

Connect the kernel to `hypothesis-generator`, `autonomous-evolution`, and `atomic_self_evolution` without changing the core promotion boundary.

### Phase 4: Honesty Gates

Add proof gates for absence, deterministic Z3 proof, heuristic non-authority, receipt stability, no direct engine writes, and no scratch-only SyGuS/CVC5 claims.

## Acceptance Criteria

The first implementation is accepted only when current-state evidence proves all of the following:

- The engine has a live synthesis kernel surface, not only documents or scratch files.
- The kernel can represent a SyGuS/CVC5 problem.
- The kernel reports missing or unreachable CVC5 as `ABSENT` with evidence.
- The kernel reports a Z3-backed fixture as `PROVEN`.
- The kernel reports heuristic output as `HEURISTIC_UNPROVEN`.
- Automatic promotion refuses anything other than `PROVEN`.
- Receipts are deterministic, hashable, and re-executable.
- Tests/gates fail if SyGuS/CVC5 only appears in docs, scratch, or stale artifacts.
- No backend writes directly to engine files.
- The implementation remains compatible with existing `atomic_self_evolution` and `atomic_expand_self` boundaries.

## Open Operational Note

The user reports CVC5 is installed. The Atomic sandbox probe used during this design did not see `cvc5` on PATH or common Homebrew paths. The implementation must therefore search configurable paths and report exact detection evidence. If CVC5 is reachable in a different host context, the receipt should show that path and version. If not reachable from Atomic, the correct runtime verdict is `ABSENT`, not failure and not success.

## Review Boundary

This document is a design specification. It authorizes writing an implementation plan after review, not direct implementation. The next step after approval of this written spec is the `superpowers:writing-plans` workflow.
