# Atomic-CLI vs Native — competitive A/B LEDGER (the loop lives here, not in chat)

Principle floor: atomic = native action-space + proof ⇒ a correct representation has capability
floor ≥ native, guarantee ceiling > native. So a LOSS is a REPRESENTATION GAP (missing macro-operator
/ fast-path / too-small micro-atomicity), never a verdict on the idea or the model. "Win with margin"
is the FALSIFIABLE target proven by number — never declared. Every atomic update is GENERALIST/UNIVERSAL
(resolves the whole CLASS, any lang/repo), applied ONLY via atomic_expand_self. Never fake green;
never compare incommensurables (same task+snapshot+model both arms or the round is void).

Commensurability note: arms MUST share the model to attribute a loss to representation (the loop's
whole point). So the valid A/B is **DeepSeek V4 Pro on BOTH arms**, varying ONLY the tooling:
- NATIVE arm = plain hand-rolled tools (grep/read/str_replace/run_tests) — the native action space.
- ATOMIC arm = atomic tools only (governed/curated), same model.
(Claude-Code-native vs DeepSeek-atomic would confound model+tooling → void round.)

## Metrics measured per round (alvo atomic em parênteses)
Pass@1 · syntactic/type/semantic regressions · invalid-states-on-disk (0) · diff surface + anchors
preserved · time / time-to-first-write · tokens / tool-calls · receipts-traces / untraced mutations (0)
· corrective rollbacks (0) · protected-touched / out-of-scope writes (0) · atomic capability gaps · manual intervention (0).

## Rounds

### Round 1 — Level 1 (SWE-bench Verified smoke, 3 tasks) — ATOMIC LOST
- arms: ATOMIC=full (115 tools) vs NATIVE=off(plain). model DeepSeek V4 Pro. snapshot: smoke3.
- result: ATOMIC 1/3 resolved, NATIVE 2/3. ATOMIC also thrashed (sympy: native 14 steps→pass; atomic 321 steps→fail, 9605-char diff).
- WINNER: native (Pass@1, steps, diff). 
- LOSS CLASS (generalized): **"low-altitude operator overload"** — handing the model 115 byte-level
  operators as the steering wheel violates the principle ("byte is the floor, never the wheel").
  Representation gap = no curated, high-altitude operator surface; choice-overload degrades reasoning.
- generalist fix direction: the agent surface is curated by ALTITUDE/contribution, not raw count;
  the byte operators stay in the engine (floor), not on the agent's wheel.

### Round 2 — Level 1 (same smoke3) — testing the Round-1 fix
- arms: ATOMIC=intent (8 governed/curated: replace_text+create_file+structural reads) vs NATIVE=off.
- status: RUNNING (concurrency=1 to avoid the Round-1.5 OOM).
- (result pending — fills in on completion.)

## Representation gaps found = loop fuel (each a CLASS, each fixed via atomic_expand_self when generalized)
- [FIXED] kernel dead: atomic_expand_self fresh-runtime timeout (180s) < proof budget (1.8M) → SIGKILL.
  Fix: tool-aware timeout (kernel 1.92M, others 180s). Source-permanent, propagated. (commit 37cf0cb)
- [OPEN, CLASS=dishonest-receipt] atomic_converge reports "✅ committed/persisted" but does NOT change
  the working file (no-op in non-git ws; git-commit in /testbed → empty working diff → harness extracts
  empty patch). Violates honest-receipt law + harness-incompatible. Generalist fix: converge must write
  the working tree (or its receipt must report "no working change" honestly) — and a high-altitude
  intent-editor that the harness can read (working-tree diff) is needed.
- [OPEN, CLASS=concurrent-clobber] the emergence-loop's snapshot/rollback reverted concurrent
  uncommitted edits (stopped the loop; needs worktree isolation so autonomous evolution composes).
- [ENV] OOM at concurrency=3 on the dev host → run arms at concurrency=1.

## Next exact step
Read Round 2 result. If ATOMIC(intent) ≥ NATIVE with margin on the dominance clauses → escalate level.
If ATOMIC(intent) loses/ties → formalize the NEW loss CLASS, derive the generalist macro-operator that
closes it, implement via atomic_expand_self (generalist only), validate (all gates green, no false-green),
re-run the SAME smoke3 until dominance. Source tasks: real public-repo issues (record source) or local CodeClash.
