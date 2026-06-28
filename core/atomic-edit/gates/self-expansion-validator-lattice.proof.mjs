#!/usr/bin/env node
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const jsonMode = process.argv.includes('--json');
const sourceDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = fs.readFileSync(path.join(sourceDir, 'server-tools-self.ts'), 'utf8');
const brokerSource = fs.readFileSync(path.join(sourceDir, 'atomic-exec-broker.mjs'), 'utf8');
const brokerClientSource = fs.readFileSync(path.join(sourceDir, 'atomic-exec-broker-client.mjs'), 'utf8');
const compiledCertificateProofSource = fs.readFileSync(path.join(sourceDir, 'gates', 'compiled-mcp-y-certificate.proof.mjs'), 'utf8');
const healthCertificateProofSource = fs.readFileSync(path.join(sourceDir, 'gates', 'atomic-health-audited-certificate.proof.mjs'), 'utf8');

const requiredCommands = [
  'node build.mjs',
  'node gates/dist-live-integrity.proof.mjs --json',
  'node gates/dist-freshness.proof.mjs --json',
  'node gates/type-soundness-gate.proof.mjs --json',
  'node gates/structural-lint-gate.proof.mjs --json',
  'node gates/algebra.proof.mjs',
  'node gates/closure-universal.proof.mjs',
  'node gates/merge.proof.mjs',
  'node dist/gates/reachability-gate.proof.js',
  'node dist/gates/binding-gate.proof.js',
  'node gates/converge-operator.proof.mjs',
  'node gates/converge-symbol-mutation.proof.mjs --json',
  'node dist/gates/probe-convergence-gate.proof.js',
  'node dist/gates/formal-gate.proof.js',
  'node dist/gates/property-gate.proof.js',
  'node dist/gates/findings-delta-gate.proof.js',
  'node dist/gates/contract-edge-gate.proof.js',
  'node gates/public-contract-gate.proof.mjs --json',
  'node gates/behavior-contract-gate.proof.mjs --json',
  'node gates/atomic-product-locks.proof.mjs --json',
  'node gates/security-gate.proof.mjs --json',
  'node gates/chrome-devtools-bridge.proof.mjs --json',
  'node gates/security-monotonicity.proof.mjs --json',
  'node gates/self-expansion-validator-lattice.proof.mjs --json',
  'node gates/lattice-completeness.proof.ts --json',
  'node gates/self-evolution-harness.proof.mjs --json',
  'node gates/self-evolution-mcp-tool.proof.mjs --json',
  'node gates/self-evolution-current-champion.proof.mjs --json',
  'node gates/self-expansion-inter-process-lock.proof.mjs --json',
  'node gates/self-expansion-pending-writes.proof.mjs --json',
  'node gates/capability-genome-registry.proof.mjs --json',
  'node gates/self-evolution-disproof-consumer.proof.mjs --json',
  'node gates/self-evolution-disproof-briefing.proof.mjs --json',
  'node gates/self-evolution-lesson-rules.proof.mjs --json',
  'node gates/codex-memory-note-tool.proof.mjs --json',
  'node gates/semantic-memory-recall.proof.mjs --json',
  'node gates/fixed-model-lift.proof.mjs --json',
  'node gates/self-host-slice.proof.mjs --json',
  'node gates/agent-trust-governance.proof.mjs --json',
  'node gates/friction-router.proof.mjs --json',
  'node gates/e1-confluent-routing.proof.mjs --json',
  'node gates/coverage-ratchet.proof.mjs --json',
  'node gates/agent-independence.proof.mjs --json',
  'node gates/minimal-disproof-core.proof.mjs --json',
  'node gates/psr-witness-refinement.proof.mjs --json',
  'node gates/atomic-agent-bench.proof.mjs',
  'node gates/test-execution-gate.proof.mjs --json',
  'node gates/vitest-package-suite.proof.mjs --json',
  'node gates/multilang-supply-chain-resolver.proof.mjs --json',
  'node gates/h2-harness-contract.proof.mjs --json',
  'node gates/h2-harness-runner.proof.mjs --json',
  'node gates/h2-experiment-harness.proof.mjs --json',
  'node gates/h2-ledger-bridge.proof.mjs --json',
  'node proof-chain.proof.mjs --json',
  'node gates/proof-snapshot-compact.proof.mjs --json',
  'node gates/proof-ledger-external-root.proof.mjs --json',
  'node gates/y-certificate-mandatory-domains.proof.mjs --json',
  'node gates/meta-synth-engine.proof.mjs --json',
  'node gates/continuous-emergence-loop.proof.mjs --json',
  'node gates/codex-entrypoint-contract.proof.mjs --json',
  'node gates/agent-hook-runtime-boundary.proof.mjs --json',
  'node gates/opencode-allin-permission-policy.proof.mjs --json',
  'node gates/compiled-mcp-y-certificate.proof.mjs --json',
  'node gates/atomic-health-audited-certificate.proof.mjs --json',
  'node gates/atomic-exec-readonly-usability.proof.mjs --json',
  'node gates/atomic-exec-output-compact.proof.mjs --json',
  'node gates/mcp-tool-list-compact.proof.mjs --json',
  'node gates/doc-honesty.proof.mjs --json',
  'node gates/readcode-missing-path-recovery.proof.mjs --json',
  'node gates/readcode-selector-error-no-recovery.proof.mjs --json',
  'node gates/effect-metadata-mode.proof.mjs --json',
  'node gates/effect-snapshot-honest-ceiling.proof.mjs --json',
  'node gates/atomic-exec-prove-effect-required.proof.mjs --json',
  'node gates/atomic-exec-indirection-denial.proof.mjs --json',
  'node gates/self-expansion-unexpected-effects.proof.mjs --json',
  'node gates/self-expansion-rollback-ephemeral-residual.proof.mjs --json',
  'node gates/self-expansion-real-self-evolution.proof.mjs --json',
  'node gates/atsh-host-boundary.proof.mjs --json',
  'node gates/atx-atomic-cli.proof.mjs --json',
  'node codex-atomic-only-hook.proof.mjs --json',
];

const requiredPhases = [
  'build',
  'runtime-integrity',
  'runtime-freshness',
  'type',
  'semantic',
  'semantic-impact',
  'reachability',
  'binding',
  'convergence',
  'runtime-probe',
  'formal',
  'property',
  'findings-delta',
  'contract-edge',
  'public-contract',
  'behavior',
  'coordination',
  'security',
  'monotonicity',
  'self-lattice',
  'self-evolution',
  'self-evolution-tool',
  'self-evolution-current-champion',
  'self-expansion-concurrency',
  'self-expansion-pending-writes',
  'capability-genome',
  'self-evolution-disproof',
  'self-evolution-disproof-briefing',
  'self-evolution-lessons',
  'codex-memory',
  'semantic-memory-recall',
  'fixed-model-lift',
  'self-evolution-real',
  'benchmark',
  'test',
  'supply-chain',
  'h2-harness-contract',
  'h2-harness-runner',
  'h2-experiment-harness',
  'h2-ledger-bridge',
  'ledger',
  'certificate',
  'formal-synthesis',
  'continuous-emergence',
  'runtime',
  'health-audited',
  'agent-runtime',
  'usability',
  'doc-honesty',
  'effect-metadata',
  'effect-admission',
  'effect-scope',
  'host-shell',
  'cli-surface',
  'no-bypass',
];

function record(results, name, ok, detail) {
  results.push({ name, ok: Boolean(ok), detail });
}

function main() {
  const results = [];
  const missing = requiredCommands.filter((command) => !source.includes(command));
  const missingPhases = requiredPhases.filter((phase) => !source.includes(`phase: '${phase}'`));
  record(
    results,
    'atomic_expand_self has a mandatory validator lattice beyond typecheck, including runtime-freshness, offline reachability, binding, formal, property, findings-delta, contract-edge, runtime-probe, semantic-impact, supply-chain, public Vitest, effect snapshot honesty, monotonicity, and read-only exec usability',
    source.includes('MANDATORY_SELF_EXPANSION_VALIDATORS') && missing.length === 0 && missingPhases.length === 0,
    { missing, missingPhases },
  );
  record(
    results,
    'caller proofCommands are additive and cannot replace mandatory validators',
    source.includes('normalizeSelfExpansionProofCommands') &&
      /(?:const|let) proofCommands = normalizeSelfExpansionProofCommands\(a\.proofCommands\);/.test(source) &&
      !source.includes("a.proofCommands ?? ['node build.mjs', 'node codex-atomic-only-hook.proof.mjs --json']"),
    {
      hasNormalizer: source.includes('normalizeSelfExpansionProofCommands'),
      oldDefaultRemoved: !source.includes("a.proofCommands ?? ['node build.mjs', 'node codex-atomic-only-hook.proof.mjs --json']"),
    },
  );
  record(
    results,
    'receipt exposes validator lattice phases instead of a flat typecheck-only proof list',
    source.includes('validatorLattice: MANDATORY_SELF_EXPANSION_VALIDATORS') &&
      source.includes('phase') &&
      source.includes('runtime-freshness') &&
      source.includes('semantic') &&
      source.includes('semantic-impact') &&
      source.includes('reachability') &&
      source.includes('binding') &&
      source.includes('convergence') &&
      source.includes('runtime-probe') &&
      source.includes('formal') &&
      source.includes('property') &&
      source.includes('findings-delta') &&
      source.includes('contract-edge') &&
      source.includes('security') &&
      source.includes('monotonicity') &&
      source.includes('self-evolution') &&
      source.includes('self-evolution-tool') &&
      source.includes('self-expansion-concurrency') &&
      source.includes('self-expansion-pending-writes') &&
      source.includes('capability-genome') &&
      source.includes('self-evolution-disproof-briefing') &&
      source.includes('runtime') &&
      source.includes('agent-runtime') &&
      source.includes('formal-synthesis') &&
      source.includes('meta-synth-engine.proof.mjs') &&
      source.includes('continuous-emergence') &&
      source.includes('continuous-emergence-loop.proof.mjs') &&
      source.includes('semantic-memory-recall') &&
      source.includes('semantic-memory-recall.proof.mjs') &&
      source.includes('usability') &&
      source.includes('host-shell') &&
      source.includes('cli-surface') &&
      source.includes('atx-atomic-cli.proof.mjs'),
    {
      hasReceipt: source.includes('validatorLattice: MANDATORY_SELF_EXPANSION_VALIDATORS'),
      hasPhase: source.includes('phase'),
      hasRuntimeFreshness: source.includes('runtime-freshness'),
      hasSemanticImpact: source.includes('semantic-impact'),
      hasReachability: source.includes('reachability'),
      hasBinding: source.includes('binding'),
      hasConvergence: source.includes('convergence'),
      hasRuntimeProbe: source.includes('runtime-probe'),
      hasFormal: source.includes('formal'),
      hasProperty: source.includes('property'),
      hasFindingsDelta: source.includes('findings-delta'),
      hasContractEdge: source.includes('contract-edge'),
      hasMonotonicity: source.includes('monotonicity'),
      hasSelfEvolution: source.includes('self-evolution'),
      hasSelfEvolutionTool: source.includes('self-evolution-tool'),
      hasSelfExpansionConcurrency: source.includes('self-expansion-concurrency'),
      hasSelfExpansionPendingWrites: source.includes('self-expansion-pending-writes'),
      hasCapabilityGenome: source.includes('capability-genome'),
      hasSelfEvolutionDisproof: source.includes('self-evolution-disproof'),
      hasSelfEvolutionDisproofBriefing: source.includes('self-evolution-disproof-briefing'),
      hasFormalSynthesis: source.includes('formal-synthesis'),
      hasMetaSynthEngine: source.includes('meta-synth-engine.proof.mjs'),
      hasContinuousEmergence: source.includes('continuous-emergence'),
      hasContinuousEmergenceLoop: source.includes('continuous-emergence-loop.proof.mjs'),
      hasSemanticMemoryRecall:
        source.includes('semantic-memory-recall') && source.includes('semantic-memory-recall.proof.mjs'),
      hasUsability: source.includes('usability'),
      hasHostShell: source.includes('host-shell'),
      hasCliSurface: source.includes('cli-surface'),
      hasAtxAtomicCliProof: source.includes('atx-atomic-cli.proof.mjs'),
    },
  );
  const handlerAwaitsProofs =
    source.includes('const executedProofs = await runProofCommands(proofCommands)') ||
    source.includes('const executedProofs = await runProofCommands(proofCommands, proofGlobalBudgetOverrideMs)');
  record(
    results,
    'self-expansion proof runner runs build first, then bounded parallel validators, and the handler awaits the proof promise',
    source.includes('const SELF_EXPANSION_PROOF_CONCURRENCY') &&
      source.includes('async function runProofCommands') &&
      handlerAwaitsProofs &&
      source.includes("executedProofs.some((p) => p.command === 'node build.mjs' && p.ok)") &&
      source.includes('const proofs = buildPassed ? [...executedProofs, ...buildCoveredProofs] : executedProofs') &&
      source.includes('covered-by-build: node build.mjs') &&
      source.includes('Promise.all') &&
      source.includes('runSingleProofCommand') &&
      /commands\[0\]\s*===\s*'node build\.mjs'/.test(source) &&
      source.includes('skipped after node build.mjs failed'),
    {
      hasConcurrencyConstant: source.includes('const SELF_EXPANSION_PROOF_CONCURRENCY'),
      runProofCommandsAsync: source.includes('async function runProofCommands'),
      handlerAwaitsProofs,
      hasParallelBatch: source.includes('Promise.all'),
      hasSingleProofRunner: source.includes('runSingleProofCommand'),
      buildFirst: /commands\[0\]\s*===\s*'node build\.mjs'/.test(source),
      hasBuildFailureSkip: source.includes('skipped after node build.mjs failed'),
    },
  );
  const lifecycleLockIndex = source.indexOf('return await withSelfExpansionAdmission(async () =>');
  const lockedSnapshotIndex = source.indexOf('const snap = captureSelfExpansionSnapshot(selfRoot, ops);', lifecycleLockIndex);
  const lockedApplyIndex = source.indexOf('ops.map((op) => applySelfFileOp(op, guardedSelfPaths));', lifecycleLockIndex);
  record(
    results,
    'self-expansion inter-process admission lock covers snapshot, apply, proof, rollback, and promotion as one transaction',
    lifecycleLockIndex >= 0 &&
      lockedSnapshotIndex > lifecycleLockIndex &&
      lockedApplyIndex > lockedSnapshotIndex &&
      !source.includes('const applied = withSelfExpansionAdmission(() => ops.map((op) => applySelfFileOp(op, guardedSelfPaths)))'),
    {
      hasLifecycleLock: lifecycleLockIndex >= 0,
      snapshotInsideLifecycleLock: lockedSnapshotIndex > lifecycleLockIndex,
      applyInsideLifecycleLock: lockedApplyIndex > lockedSnapshotIndex,
      oldWriteOnlyLockRemoved: !source.includes('const applied = withSelfExpansionAdmission(() => ops.map((op) => applySelfFileOp(op, guardedSelfPaths)))'),
    },
  );
  const directTimeoutResolves = /setTimeout\(\(\) => \{[\s\S]*atomic proof timed out after[\s\S]*setTimeout\(forceKill, 1000\)\.unref\(\);\n\s*finish\(\{ command, ok: false[\s\S]*\}, timeoutMs\);/.test(source);
  const brokerTimeoutResolves = /setTimeout\(\(\) => \{[\s\S]*atomic proof broker timed out after[\s\S]*setTimeout\(forceKill, 1000\)\.unref\(\);\n\s*finish\(\{ command, ok: false[\s\S]*\}, timeoutMs \+ 5000\);/.test(source);
  const hasPerCallBudgetSchema = /proofGlobalBudgetMs:\s*z\s*\.\s*number\(\)\s*\.\s*int\(\)\s*\.\s*min\(30000\)\s*\.\s*max\(14400000\)\s*\.\s*optional\(\)/.test(source);
  record(
    results,
    'self-expansion has a per-call bounded global proof deadline and scaled default for large validator lattices',
    source.includes('const SELF_EXPANSION_PROOF_GLOBAL_BUDGET_MS = 240000') &&
      source.includes('const SELF_EXPANSION_PROOF_MIN_COMMAND_MS = 12000') &&
      source.includes('function proofGlobalBudgetMs(requested?: number, commandCount = MANDATORY_SELF_EXPANSION_VALIDATORS.length): number') &&
      source.includes('Math.max(SELF_EXPANSION_PROOF_GLOBAL_BUDGET_MS, commandCount * SELF_EXPANSION_PROOF_MIN_COMMAND_MS)') &&
      source.includes('proofGlobalBudgetMs(proofGlobalBudgetOverrideMs, commands.length)') &&
      hasPerCallBudgetSchema &&
      source.includes('remainingProofBudgetMs') &&
      source.includes('proofTimeoutForDeadline') &&
      source.includes('self-expansion proof global budget exhausted') &&
      directTimeoutResolves &&
      brokerTimeoutResolves,
    {
      hasMinimumBaseBudget: source.includes('const SELF_EXPANSION_PROOF_GLOBAL_BUDGET_MS = 240000'),
      hasPerCommandBudgetFloor: source.includes('const SELF_EXPANSION_PROOF_MIN_COMMAND_MS = 12000'),
      hasScaledBudgetFunction: source.includes('function proofGlobalBudgetMs(requested?: number, commandCount = MANDATORY_SELF_EXPANSION_VALIDATORS.length): number'),
      computesScaledDefault: source.includes('Math.max(SELF_EXPANSION_PROOF_GLOBAL_BUDGET_MS, commandCount * SELF_EXPANSION_PROOF_MIN_COMMAND_MS)'),
      runProofCommandsPassesCommandCount: source.includes('proofGlobalBudgetMs(proofGlobalBudgetOverrideMs, commands.length)'),
      hasPerCallBudgetSchema,
      hasRemainingBudget: source.includes('remainingProofBudgetMs'),
      hasDeadlineTimeout: source.includes('proofTimeoutForDeadline'),
      hasBudgetFailureText: source.includes('self-expansion proof global budget exhausted'),
      directTimeoutResolves,
      brokerTimeoutResolves,
    },
  );
  record(
    results,
    'self-expansion gives liveness-critical validators explicit sub-client timeout budgets',
    source.includes("command.includes('type-soundness-gate')") &&
      source.includes("command.includes('algebra.proof.mjs')") &&
      source.includes("command.includes('contract-edge-gate')") &&
      source.includes("command.includes('self-evolution-mcp-tool')") &&
      source.includes("command.includes('vitest-package-suite')") &&
      source.includes("command.includes('multilang-supply-chain-resolver')") &&
      source.includes("command.includes('meta-synth-engine')") &&
      source.includes("command.includes('compiled-mcp-y-certificate')") &&
      source.includes("command.includes('atomic-health-audited-certificate')") &&
      /return 600000;/.test(source),
    {
      hasTypeBudget: source.includes("command.includes('type-soundness-gate')"),
      hasAlgebraBudget: source.includes("command.includes('algebra.proof.mjs')"),
      hasContractEdgeBudget: source.includes("command.includes('contract-edge-gate')"),
      hasSelfEvolutionToolBudget: source.includes("command.includes('self-evolution-mcp-tool')"),
      hasVitestPackageBudget: source.includes("command.includes('vitest-package-suite')"),
      hasMultilangSupplyChainBudget: source.includes("command.includes('multilang-supply-chain-resolver')"),
      hasMetaSynthBudget: source.includes("command.includes('meta-synth-engine')"),
      hasCompiledCertificateBudget: source.includes("command.includes('compiled-mcp-y-certificate')"),
      hasAuditedHealthBudget: source.includes("command.includes('atomic-health-audited-certificate')"),
      hasLivenessBudget: /return 600000;/.test(source),
    },
  );
  record(
    results,
    'self-expansion schedules historically slow validators first while preserving original receipt order',
    source.includes('function proofCommandPriority') &&
      source.includes('compiled-mcp-y-certificate') &&
      source.includes('atomic-health-audited-certificate') &&
      source.includes('type-soundness-gate') &&
      source.includes('contract-edge-gate') &&
      source.includes('self-evolution-mcp-tool') &&
      source.includes('self-expansion-inter-process-lock') &&
      source.includes('meta-synth-engine.proof.mjs') &&
      source.includes('vitest-package-suite') &&
      source.includes('multilang-supply-chain-resolver') &&
      source.includes('queue.sort') &&
      source.includes('results[item.index]'),
    {
      hasPriorityFunction: source.includes('function proofCommandPriority'),
      prioritizesCompiledCertificate: source.includes('compiled-mcp-y-certificate'),
      prioritizesAuditedHealth: source.includes('atomic-health-audited-certificate'),
      prioritizesType: source.includes('type-soundness-gate'),
      prioritizesContractEdge: source.includes('contract-edge-gate'),
      prioritizesSelfEvolutionTool: source.includes('self-evolution-mcp-tool'),
      prioritizesSelfExpansionLock: source.includes('self-expansion-inter-process-lock'),
      prioritizesMetaSynth: source.includes('meta-synth-engine.proof.mjs'),
      prioritizesVitestPackage: source.includes('vitest-package-suite'),
      prioritizesMultilangSupplyChain: source.includes('multilang-supply-chain-resolver'),
      sortsQueue: source.includes('queue.sort'),
      preservesReceiptOrder: source.includes('results[item.index]'),
    },
  );
  record(
    results,
    'self-expansion runs socket/temp/lifetime validators host-direct with broker env suppressed',
    source.includes('function selfExpansionProofMustRunHostDirect') &&
      source.includes("'lsp-semantic-delta.proof.mjs'") &&
      source.includes("'meta-synth-engine.proof.mjs'") &&
      source.includes("'vitest-package-suite.proof.mjs'") &&
      source.includes("'multilang-supply-chain-resolver.proof.mjs'") &&
      source.includes("'resource-lifetime.proof.mjs'") &&
      source.includes("'fd-socket-lifetime.proof.mjs'") &&
      source.includes("'create-file-overwrite-negative-proof.proof.mjs'") &&
      source.includes("'converge-symbol-mutation.proof.mjs'") &&
      source.includes("'self-expansion-inter-process-lock.proof.mjs'") &&
      source.includes("'atomic-health-audited-certificate.proof.mjs'") &&
      source.includes("'atsh-host-boundary.proof.mjs'") &&
      source.includes("'atx-atomic-cli.proof.mjs'") &&
      source.includes('const mustRunHostDirect = Boolean(socket && selfExpansionProofMustRunHostDirect(command))') &&
      source.includes('const proofEnv = selfExpansionProofEnv(mustRunHostDirect ? null : socket, command)') &&
      source.includes('function pathIsInsideOrEqual(root: string, candidate: string): boolean') &&
      source.includes('function selfExpansionProofCodexHome(hostRoot: string): string') &&
      source.includes('pathIsInsideOrEqual(host, resolved)') &&
      source.includes('pathIsInsideOrEqual(selfRoot, resolved)') &&
      source.includes("const accepted = accept(path.join(home, '.codex'))") &&
      source.includes('function selfExpansionHostDirectTempRoot(hostRoot: string): string') &&
      source.includes('const codexHome = selfExpansionProofCodexHome(hostRoot)') &&
      source.includes("path.join(codexHome, 'tmp', 'atomic-self-expansion-proof')") &&
      source.includes('function selfExpansionBrokerTempRoot(hostRoot: string): string') &&
      source.includes("path.join(path.resolve(hostRoot), 'atomic-exec')") &&
      source.includes('selfExpansionProofTempRoot(hostRoot, selfExpansionProofMustRunHostDirect(command))') &&
      source.includes('CODEX_HOME: selfExpansionProofCodexHome(hostRoot)'),
    {
      hasHostDirectRouter: source.includes('function selfExpansionProofMustRunHostDirect'),
      hasLspSemanticDeltaHostDirect: source.includes("'lsp-semantic-delta.proof.mjs'"),
      hasMetaSynthHostDirect: source.includes("'meta-synth-engine.proof.mjs'"),
      hasVitestPackageHostDirect: source.includes("'vitest-package-suite.proof.mjs'"),
      hasMultilangSupplyChainHostDirect: source.includes("'multilang-supply-chain-resolver.proof.mjs'"),
      hasResourceLifetimeHostDirect: source.includes("'resource-lifetime.proof.mjs'"),
      hasFdSocketLifetimeHostDirect: source.includes("'fd-socket-lifetime.proof.mjs'"),
      hasCreateOverwriteHostDirect: source.includes("'create-file-overwrite-negative-proof.proof.mjs'"),
      hasConvergeSymbolHostDirect: source.includes("'converge-symbol-mutation.proof.mjs'"),
      hasSelfExpansionLockHostDirect: source.includes("'self-expansion-inter-process-lock.proof.mjs'"),
      hasAuditedHealthHostDirect: source.includes("'atomic-health-audited-certificate.proof.mjs'"),
      hasAtshHostDirect: source.includes("'atsh-host-boundary.proof.mjs'"),
      hasAtxCliHostDirect: source.includes("'atx-atomic-cli.proof.mjs'"),
      hostDirectSuppressesBrokerEnv: source.includes('const proofEnv = selfExpansionProofEnv(mustRunHostDirect ? null : socket, command)'),
      hostDirectUsesCodexTemp: source.includes('function selfExpansionHostDirectTempRoot(hostRoot: string): string'),
      hostDirectCodexHomeExternalized: source.includes('function selfExpansionProofCodexHome(hostRoot: string): string'),
      hostDirectRejectsRepoScopedCodexHome: source.includes('pathIsInsideOrEqual(host, resolved)'),
      hostDirectRejectsSelfScopedCodexHome: source.includes('pathIsInsideOrEqual(selfRoot, resolved)'),
      hostDirectTempAllowsUnixSockets: source.includes("path.join(codexHome, 'tmp', 'atomic-self-expansion-proof')"),
      proofEnvUsesExternalizedCodexHome: source.includes('CODEX_HOME: selfExpansionProofCodexHome(hostRoot)'),
      brokerUsesAtomicExecScratch: source.includes("path.join(path.resolve(hostRoot), 'atomic-exec')"),
    },
  );
  record(
    results,
    'self-expansion certificate proofs keep dynamic host checks outside validator mode',
    source.includes('ATOMIC_SELF_EXPANSION_VALIDATOR') &&
      compiledCertificateProofSource.includes('compiled certificate self-expansion validator mode is explicit') &&
      compiledCertificateProofSource.includes("client.callTool({ name: 'atomic_y_certificate'") &&
      compiledCertificateProofSource.includes('new StdioClientTransport') &&
      compiledCertificateProofSource.includes('selfExpansionValidatorPayload()') &&
      healthCertificateProofSource.includes('health certificate self-expansion validator mode is explicit') &&
      healthCertificateProofSource.includes("ATOMIC_SINGLE_TOOL_NAME: 'atomic_health'") &&
      healthCertificateProofSource.includes('includeAudits: true') &&
      healthCertificateProofSource.includes('selfExpansionValidatorPayload()'),
    {
      proofEnvMarksValidator: source.includes('ATOMIC_SELF_EXPANSION_VALIDATOR'),
      compiledHasValidatorMode: compiledCertificateProofSource.includes('compiled certificate self-expansion validator mode is explicit'),
      compiledKeepsDynamicMcpCall: compiledCertificateProofSource.includes("client.callTool({ name: 'atomic_y_certificate'"),
      healthHasValidatorMode: healthCertificateProofSource.includes('health certificate self-expansion validator mode is explicit'),
      healthKeepsDynamicAtomicHealth: healthCertificateProofSource.includes("ATOMIC_SINGLE_TOOL_NAME: 'atomic_health'"),
    },
  );
  record(
    results,
    'self-expansion abstains host-runtime validators only on explicit infra/sandbox absence signatures',
    source.includes("'node gates/resource-lifetime.proof.mjs --json'") &&
      source.includes("'node gates/fd-socket-lifetime.proof.mjs --json'") &&
      source.includes("'node gates/atomic-health-audited-certificate.proof.mjs --json'") &&
      source.includes("'node gates/atsh-host-boundary.proof.mjs --json'") &&
      source.includes("'node gates/atx-atomic-cli.proof.mjs --json'") &&
      source.includes('resource-lifetime\\.proof|fd-socket-lifetime\\.proof') &&
      source.includes('"ok"\\s*:\\s*false') &&
      source.includes('listen EPERM') &&
      source.includes('atomic proof timed out after') &&
      source.includes('wholeHostActionSpace'),
    {
      hasRuntimeHostDependentProofs:
        source.includes("'node gates/resource-lifetime.proof.mjs --json'") &&
        source.includes("'node gates/fd-socket-lifetime.proof.mjs --json'"),
      hasHealthAtshAtxHostDependentProofs:
        source.includes("'node gates/atomic-health-audited-certificate.proof.mjs --json'") &&
        source.includes("'node gates/atsh-host-boundary.proof.mjs --json'") &&
        source.includes("'node gates/atx-atomic-cli.proof.mjs --json'"),
      hasOkFalseRuntimeSignature: source.includes('"ok"\\s*:\\s*false'),
      hasAtshSignature: source.includes('listen EPERM'),
      hasAtxTimeoutSignature: source.includes('atomic proof timed out after'),
      hasHealthHostBoundarySignature: source.includes('wholeHostActionSpace'),
    },
  );
  record(
    results,
    'self-expansion proof env scrubs single-tool delegation vars for both broker and direct fallback paths',
    source.includes('function selfExpansionProofEnv(socket: string | null, command: string)') &&
      source.includes('delete cleanProofEnv.ATOMIC_SINGLE_TOOL_CALL') &&
      source.includes('delete cleanProofEnv.ATOMIC_SINGLE_TOOL_NAME') &&
      source.includes('delete cleanProofEnv.ATOMIC_SINGLE_TOOL_ARGS_JSON') &&
      source.includes('const proofEnv = selfExpansionProofEnv(mustRunHostDirect ? null : socket, command)') &&
      source.includes('runProofCommandDirect(command, cwd, timeout, proofEnv)') &&
      source.includes("ATOMIC_SINGLE_TOOL_CALL: ''") &&
      source.includes("ATOMIC_SINGLE_TOOL_NAME: ''") &&
      source.includes("ATOMIC_SINGLE_TOOL_ARGS_JSON: ''"),
    {
      hasUnifiedProofEnv: source.includes('function selfExpansionProofEnv(socket: string | null, command: string)'),
      scrubsCall: source.includes('delete cleanProofEnv.ATOMIC_SINGLE_TOOL_CALL'),
      scrubsName: source.includes('delete cleanProofEnv.ATOMIC_SINGLE_TOOL_NAME'),
      scrubsArgs: source.includes('delete cleanProofEnv.ATOMIC_SINGLE_TOOL_ARGS_JSON'),
      directFallbackUsesProofEnv: source.includes('runProofCommandDirect(command, cwd, timeout, proofEnv)'),
      brokerOverridesSingleToolCall: source.includes("ATOMIC_SINGLE_TOOL_CALL: ''"),
      brokerOverridesSingleToolName: source.includes("ATOMIC_SINGLE_TOOL_NAME: ''"),
      brokerOverridesSingleToolArgs: source.includes("ATOMIC_SINGLE_TOOL_ARGS_JSON: ''"),
    },
  );
  record(
    results,
    'self-expansion proof temp roots separate host-direct sockets from broker atomic-exec scratch',
    source.includes('function selfExpansionProofTempRoot(hostRoot: string, preferHostDirect = false)') &&
      source.includes('const selfRoot = path.resolve(atomicSelfSourceRoot())') &&
      source.includes('const insideSelfRoot = requested === selfRoot || requested.startsWith(selfRoot + path.sep)') &&
      source.includes('const insideHostRoot = requested === host || requested.startsWith(host + path.sep)') &&
      source.includes('if (requested && !insideSelfRoot && !insideHostRoot) return requested') &&
      source.includes("path.join(host, '.atomic', 'self-expansion-proof-tmp')") &&
      source.includes('const brokerTempRoot = proofEnv.TMPDIR ?? selfExpansionBrokerTempRoot(brokerRoot)') &&
      source.includes("const brokerEndpointRoot = socket.startsWith('file://') ? fileURLToPath(socket) : null") &&
      source.includes('const brokerWriteRoots = brokerEndpointRoot ? [brokerEndpointRoot] : []') &&
      source.includes('tempRoot: brokerTempRoot') &&
      source.includes('writeRoots: brokerWriteRoots'),
    {
      hasSafeTempRootFunction: source.includes('function selfExpansionProofTempRoot(hostRoot: string, preferHostDirect = false)'),
      checksSelfRoot: source.includes('insideSelfRoot'),
      checksHostRoot: source.includes('insideHostRoot'),
      acceptsExternalTmp: source.includes('if (requested && !insideSelfRoot && !insideHostRoot) return requested'),
      brokerUsesAtomicExecScratch: source.includes('const brokerTempRoot = proofEnv.TMPDIR ?? selfExpansionBrokerTempRoot(brokerRoot)'),
      brokerAllowsNestedBrokerEndpoint: source.includes('const brokerWriteRoots = brokerEndpointRoot ? [brokerEndpointRoot] : []'),
      brokerRequestPassesTempRoot: source.includes('tempRoot: brokerTempRoot'),
      brokerRequestPassesWriteRoots: source.includes('writeRoots: brokerWriteRoots'),
    },
  );
  record(
    results,
    'file broker clients validate marker, owner process, and queue directories before writing a request and while waiting for a response',
    brokerClientSource.includes("broker file endpoint unavailable") &&
      brokerClientSource.includes("fs.readFileSync(path.join(root, 'broker.json')") &&
      brokerClientSource.includes("marker?.protocol !== 'atomic-file-broker-v1'") &&
      brokerClientSource.includes('process.kill(marker.pid, 0)') &&
      brokerClientSource.includes('const markerUnavailableReason = () =>') &&
      brokerClientSource.includes('missing marker during wait') &&
      brokerClientSource.includes("return 'queue directories missing during wait'") &&
      brokerClientSource.includes("fs.rmSync(requestFile + '.processing', { force: true })") &&
      brokerClientSource.indexOf('writeJsonAtomic(requestFile, req)') > brokerClientSource.indexOf("!fs.statSync(requests).isDirectory()") &&
      brokerClientSource.lastIndexOf('const unavailableReason = markerUnavailableReason();') > brokerClientSource.indexOf('writeJsonAtomic(requestFile, req)') &&
      brokerClientSource.lastIndexOf('const unavailableReason = markerUnavailableReason();') < brokerClientSource.indexOf('if (Date.now() > deadline)'),
    {
      hasUnavailableMarker: brokerClientSource.includes('broker file endpoint unavailable'),
      readsMarker: brokerClientSource.includes("fs.readFileSync(path.join(root, 'broker.json')"),
      validatesProtocol: brokerClientSource.includes("marker?.protocol !== 'atomic-file-broker-v1'"),
      probesOwner: brokerClientSource.includes('process.kill(marker.pid, 0)'),
      revalidatesDuringWait: brokerClientSource.includes('const markerUnavailableReason = () =>') && brokerClientSource.includes('missing marker during wait'),
      cleansQueuedRequest: brokerClientSource.includes("fs.rmSync(requestFile + '.processing', { force: true })"),
      writesAfterValidation:
        brokerClientSource.indexOf('writeJsonAtomic(requestFile, req)') > brokerClientSource.indexOf("!fs.statSync(requests).isDirectory()"),
      waitValidationBeforeDeadline:
        brokerClientSource.lastIndexOf('const unavailableReason = markerUnavailableReason();') > brokerClientSource.indexOf('writeJsonAtomic(requestFile, req)') &&
        brokerClientSource.lastIndexOf('const unavailableReason = markerUnavailableReason();') < brokerClientSource.indexOf('if (Date.now() > deadline)'),
    },
  );
  record(
    results,
    'atomic exec broker handles concurrent proof clients asynchronously while preserving per-command sandbox execution',
    brokerSource.includes("import { spawn } from 'node:child_process';") &&
      !brokerSource.includes("import { spawnSync } from 'node:child_process';") &&
      /async function handle\(/.test(brokerSource) &&
      /await handle\(/.test(brokerSource) &&
      brokerSource.includes('function runSandboxed') &&
      brokerSource.includes('new Promise') &&
      brokerSource.includes('Array.isArray(req.writeRoots)') &&
      brokerSource.includes("broker: writeRoot escapes allowed roots") &&
      brokerSource.includes('profile(eRoot, profileName, tempRoot, extraWriteRoots)'),
    {
      importsSpawn: brokerSource.includes("import { spawn } from 'node:child_process';"),
      removedSpawnSyncImport: !brokerSource.includes("import { spawnSync } from 'node:child_process';"),
      hasAsyncHandle: /async function handle\(/.test(brokerSource),
      awaitsHandle: /await handle\(/.test(brokerSource),
      hasSandboxRunner: brokerSource.includes('function runSandboxed'),
      hasPromiseRunner: brokerSource.includes('new Promise'),
      validatesExtraWriteRoots: brokerSource.includes('Array.isArray(req.writeRoots)'),
      rejectsEscapingWriteRoots: brokerSource.includes("broker: writeRoot escapes allowed roots"),
      appliesExtraWriteRootsToProfile: brokerSource.includes('profile(eRoot, profileName, tempRoot, extraWriteRoots)'),
    },
  );
  return { ok: results.every((entry) => entry.ok), results };
}

const payload = main();
if (jsonMode) process.stdout.write(JSON.stringify(payload, null, 2) + '\n');
else for (const entry of payload.results) process.stdout.write(`${entry.ok ? 'PASS' : 'FAIL'} ${entry.name}\n`);
process.exit(payload.ok ? 0 : 1);
