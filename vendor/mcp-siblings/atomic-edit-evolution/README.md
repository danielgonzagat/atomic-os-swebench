# atomic-edit-evolution

Darwin-Gödel self-evolution infrastructure for the atomic-edit system.

## Modules

| Module | Purpose |
|--------|---------|
| `truth-funnel.mjs` | P9/P10: verifier-gated answers + byte-positive monotone convergence |
| `friction-router.mjs` | Stigmergic, friction-routed multi-agent coordination |
| `emergence-benchmark.mjs` | A/B comparison: truth-funnel vs blind-retry (synthetic + live LLM) |
| `four-arm-benchmark.mjs` | 4-arm: raw vs funnel vs routing vs fusion (c⋆) |
| `sweet-spot-calibrator.mjs` | Measures model P per task, identifies emergence sweet-spot |
| `cross-task-learning.mjs` | Tests if disproof lesson from Batch 1 improves Batch 2 |
| `corpus-accumulator.mjs` | Runs gates, records REDs as witness records in corpus |
| `llm-hypothesis-generator.mjs` | LLM formulates causal hypotheses about statistical couplings |
| `admit-synthesized-gate.mjs` | Automates gate synthesis → verification → admission pipeline |
| `multi-domain-emergence.mjs` | Task families: Python, Go, Rust, creative (haiku, acrostic, rhyme) |
| `emergence-dashboard.html` | Metrics dashboard |

## Quick Start

```bash
# Prove emergence mechanism (deterministic, 200 trials)
node emergence-benchmark.mjs

# Run 4-arm comparison
node four-arm-benchmark.mjs

# Calibrate a model's sweet-spot
node sweet-spot-calibrator.mjs --synthetic

# Run the closed Darwin-Gödel loop (from atomic-edit root)
node continuous-emergence-loop.mjs --once

# Accumulate corpus from gate failures
node corpus-accumulator.mjs

# See friction routing from corpus
node friction-integration.mjs
```

## The Darwin-Gödel Loop

```
corpus-accumulator → hypothesis-generator → autonomous-evolution → emergence-observatory
     ↑                                                                        |
     └──────────────── self-reinforcing feedback cycle ─────────────────────┘
```

Each cycle:
1. Runs gates, records failures as witness records
2. Mines statistical couplings from the enriched corpus
3. Synthesizes self-contained proof gates from the strongest coupling
4. Measures deviation signals (novelty, niche, topology)

The loop runs every 2 hours via launchd (`continuous-emergence-loop.plist`).

## Honest Boundaries

- Emergence requires P(unit) ∈ (0,1) — the model's capability edge
- For current LLMs on well-defined tasks, P is approximately binary
- The sweet-spot is narrow but real (proven by 300 trials × 6 configs)
- Cross-task learning requires systematic error patterns that transfer
- Sandbox proofs need non-nested execution context (macOS limitation)
