#!/usr/bin/env node
import { appendProposalJsonl } from '../experiment-harness.mjs';
import { buildH2Fixture, sha256 } from '../h2-harness-runner.mjs';
import {
  buildH2LedgerBridgeReceipt,
  evaluateH2LedgerBridgeReceipt,
  runH2LedgerBridge,
} from '../h2-ledger-bridge.mjs';

const jsonMode = process.argv.includes('--json');
/** @type {{name: string, ok: boolean, detail: unknown}[]} */
const results = [];
const DEFAULT_SEEDS = Object.freeze(['s1', 's2', 's3', 's4', 's5']);

/** @param {string} name @param {boolean} ok @param {unknown} [detail] */
function record(name, ok, detail = {}) {
  results.push({ name, ok: Boolean(ok), detail });
}

/** @param {unknown} entries @param {string} code @returns {boolean} */
function hasCode(entries, code) {
  return Array.isArray(entries) && entries.some((entry) => entry && typeof entry === 'object' && entry.code === code);
}

/** @template T @param {T} value @returns {T} */
function clone(value) {
  return /** @type {T} */ (JSON.parse(JSON.stringify(value)));
}

/** @param {{sourceArm: string, start: number, step: number, seeds?: readonly string[], iterations?: number}} args */
function makeLedger(args) {
  const seeds = args.seeds ?? DEFAULT_SEEDS;
  const iterations = args.iterations ?? 8;
  let ledgerText = '';
  for (let seedIndex = 0; seedIndex < seeds.length; seedIndex += 1) {
    const seed = seeds[seedIndex];
    const seedOffset = (seedIndex - 2) * 0.0005;
    for (let generation = 1; generation <= iterations; generation += 1) {
      const publicScore = Number((args.start + args.step * (generation - 1) + seedOffset).toFixed(4));
      const proposalArgs = {
        arm: args.sourceArm,
        seed,
        generation,
        taskId: 'h2-ledger-bridge-proof',
        basePromptVersion: 'frozen-proposer-v1',
        promptSha256: sha256(`prompt:${args.sourceArm}:${seed}:${generation}`),
        briefingDigest: args.sourceArm === 'ESCALAR' ? null : sha256(`briefing:${args.sourceArm}:${seed}:${generation}`),
        shadowCount: args.sourceArm === 'GRADIENTE_SOMBRA' ? 1 : 0,
        proposalDigest: sha256(`proposal:${args.sourceArm}:${seed}:${generation}:${publicScore}`),
        diffText: `diff ${args.sourceArm} ${seed} g${generation} score=${publicScore}`,
        verdict: { decision: 'promote' },
        publicScore,
        unjudged: false,
      };
      const appended = appendProposalJsonl({ ledgerText, proposalArgs });
      if (appended.ok !== true) throw new Error(`append failed for ${args.sourceArm}/${seed}/g${generation}: ${appended.error}`);
      ledgerText = appended.ledgerText;
    }
  }
  return { ledgerText, sourceArm: args.sourceArm, sourceLabel: `${args.sourceArm}:${args.start}:${args.step}` };
}

function makePassingArmLedgers() {
  return {
    C: makeLedger({ sourceArm: 'GRADIENTE_SOMBRA', start: 0.2, step: 0.06 }),
    A1: makeLedger({ sourceArm: 'GRADIENTE', start: 0.2, step: 0.02 }),
    A2: makeLedger({ sourceArm: 'GRADIENTE', start: 0.2, step: 0.015 }),
    PERM: makeLedger({ sourceArm: 'ESCALAR', start: 0.2, step: 0.001 }),
  };
}

const baseReceipt = buildH2Fixture('pass');
const passing = runH2LedgerBridge({ armLedgers: makePassingArmLedgers(), baseReceipt, scoreScale: 1 });
record(
  'verified III.f ledgers for all four H2 arms can be bridged into a PASS receipt only with a supplied control receipt',
  passing.evaluation.result.verdict === 'PASS' &&
    passing.evaluation.result.validForH2Claim === true &&
    passing.evaluation.result.bridgeFailures.length === 0 &&
    passing.evaluation.experimentReceiptHash.valid === true,
  passing.evaluation.result,
);

record(
  'bridge preserves source lineage heads and derives raw H2 traces before rescore',
  passing.receipt.ledgerBridge.sourceLedgerCount === 4 &&
    typeof passing.receipt.ledgerBridge.sourceLedgers.C.chainHead === 'string' &&
    passing.receipt.experiment.rawArms.C.length === 5 &&
    passing.receipt.experiment.rawArms.C.every((series) => series.points.length === 8) &&
    passing.evaluation.rescore.derivedFieldsRecomputed === true &&
    passing.evaluation.rescore.fieldMismatches.length === 0,
  {
    sourceLedgers: passing.receipt.ledgerBridge.sourceLedgers,
    cPoints: passing.receipt.experiment.rawArms.C[0].points,
  },
);

const withoutControls = runH2LedgerBridge({ armLedgers: makePassingArmLedgers(), scoreScale: 1 });
record(
  'ledger curves alone are VOID without a separate H2 control receipt',
  withoutControls.evaluation.result.verdict === 'VOID' &&
    withoutControls.evaluation.result.validForH2Claim === false &&
    hasCode(withoutControls.evaluation.result.protocolFailures, 'H2_LEDGER_CONTROL_RECEIPT_MISSING'),
  withoutControls.evaluation.result,
);

const underInstrumented = runH2LedgerBridge({
  armLedgers: {
    C: makeLedger({ sourceArm: 'GRADIENTE_SOMBRA', start: 0.2, step: 0.06 }),
    A1: makeLedger({ sourceArm: 'GRADIENTE', start: 0.2, step: 0.02 }),
  },
  baseReceipt,
  scoreScale: 1,
});
record(
  'under-instrumented two-arm real-run data is VOID, not silently promoted to H2 evidence',
  underInstrumented.evaluation.result.verdict === 'VOID' &&
    hasCode(underInstrumented.evaluation.result.protocolFailures, 'H2_LEDGER_ARM_MISSING'),
  underInstrumented.evaluation.result,
);

const tamperedLedgers = makePassingArmLedgers();
tamperedLedgers.C = {
  ...tamperedLedgers.C,
  ledgerText: tamperedLedgers.C.ledgerText.replace(/"publicScore":[0-9.]+/, '"publicScore":0.95'),
};
const tampered = runH2LedgerBridge({ armLedgers: tamperedLedgers, baseReceipt, scoreScale: 1 });
record(
  'tampered source run-ledger chain is VOID before H2 rescore can be treated as evidence',
  tampered.evaluation.result.verdict === 'VOID' &&
    hasCode(tampered.evaluation.result.protocolFailures, 'H2_LEDGER_CHAIN_INVALID'),
  tampered.evaluation.result,
);

const lowSeeds = makePassingArmLedgers();
lowSeeds.C = makeLedger({ sourceArm: 'GRADIENTE_SOMBRA', start: 0.2, step: 0.06, seeds: ['s1', 's2', 's3', 's4'] });
const lowSeedResult = runH2LedgerBridge({ armLedgers: lowSeeds, baseReceipt, scoreScale: 1 });
record(
  'source arms with too few independent seeds are VOID even if the aggregate curve shape looks strong',
  lowSeedResult.evaluation.result.verdict === 'VOID' &&
    hasCode(lowSeedResult.evaluation.result.protocolFailures, 'H2_LEDGER_SEEDS_TOO_LOW'),
  lowSeedResult.evaluation.result,
);

const lowIterations = makePassingArmLedgers();
lowIterations.C = makeLedger({ sourceArm: 'GRADIENTE_SOMBRA', start: 0.2, step: 0.06, iterations: 7 });
const lowIterationResult = runH2LedgerBridge({ armLedgers: lowIterations, baseReceipt, scoreScale: 1 });
record(
  'source arms with too few iterations are VOID at the bridge boundary',
  lowIterationResult.evaluation.result.verdict === 'VOID' &&
    hasCode(lowIterationResult.evaluation.result.protocolFailures, 'H2_LEDGER_ITERATIONS_TOO_LOW'),
  lowIterationResult.evaluation.result,
);

const sourceMetadataTamper = buildH2LedgerBridgeReceipt({ armLedgers: makePassingArmLedgers(), baseReceipt, scoreScale: 1 });
sourceMetadataTamper.ledgerBridge.sourceLedgers.C.chainHead = 'forged-chain-head';
const sourceMetadataTamperEval = evaluateH2LedgerBridgeReceipt(sourceMetadataTamper);
record(
  'post-finalization source metadata tamper invalidates the bridge receipt and is VOID',
  sourceMetadataTamperEval.result.verdict === 'VOID' &&
    sourceMetadataTamperEval.experimentReceiptHash.valid === false &&
    hasCode(sourceMetadataTamperEval.result.protocolFailures, 'H2_LEDGER_RECEIPT_HASH_MISMATCH'),
  sourceMetadataTamperEval,
);

const rawTraceTamper = buildH2LedgerBridgeReceipt({ armLedgers: makePassingArmLedgers(), baseReceipt, scoreScale: 1 });
for (const point of rawTraceTamper.experiment.rawArms.C[0].points) point.resolve = 0.2;
const rawTraceTamperEval = evaluateH2LedgerBridgeReceipt(rawTraceTamper);
record(
  'post-finalization raw trace tamper is detected by hash mismatch and cannot remain a valid H2 claim',
  rawTraceTamperEval.result.verdict === 'VOID' &&
    rawTraceTamperEval.result.validForH2Claim === false &&
    rawTraceTamperEval.experimentReceiptHash.valid === false,
  rawTraceTamperEval,
);

const ok = results.every((result) => result.ok);
const payload = { ok, gate: 'h2-ledger-bridge', results };
if (jsonMode) {
  process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
} else {
  for (const result of results) process.stdout.write(`${result.ok ? 'PASS' : 'FAIL'} ${result.name}\n`);
}
process.exit(ok ? 0 : 1);
