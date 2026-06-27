#!/usr/bin/env node
import {
  buildH2ExperimentReceipt,
  computeH2ExperimentReceiptHash,
  rescoreH2ExperimentReceipt,
  runH2Experiment,
} from '../h2-experiment-harness.mjs';

const jsonMode = process.argv.includes('--json');
/** @type {{name: string, ok: boolean, detail: unknown}[]} */
const results = [];

/** @param {string} name @param {boolean} ok @param {unknown} [detail] */
function record(name, ok, detail = {}) {
  results.push({ name, ok: Boolean(ok), detail });
}

/** @param {unknown} entries @param {string} code @returns {boolean} */
function hasCode(entries, code) {
  return Array.isArray(entries) && entries.some((entry) => entry && typeof entry === 'object' && entry.code === code);
}

/** @param {ReturnType<typeof rescoreH2ExperimentReceipt>} rescore @param {string} field @returns {boolean} */
function hasMismatch(rescore, field) {
  return Array.isArray(rescore.fieldMismatches) && rescore.fieldMismatches.includes(field);
}

const passA = runH2Experiment('pass');
const passB = runH2Experiment('pass');
record(
  'deterministic H2 experiment receipt is hash-stable from preregistered seeds and raw traces',
  passA.receipt.experimentReceiptSha256 === passB.receipt.experimentReceiptSha256 &&
    passA.receipt.experimentReceiptSha256 === computeH2ExperimentReceiptHash(passA.receipt) &&
    passA.rescore.experimentReceiptHash.valid === true,
  { firstHash: passA.receipt.experimentReceiptSha256, secondHash: passB.receipt.experimentReceiptSha256 },
);

record(
  'independent rescore recomputes fields from raw traces and yields PASS for the coupled scenario',
  passA.rescore.derivedFieldsRecomputed === true &&
    passA.rescore.fieldMismatches.length === 0 &&
    passA.rescore.result.verdict === 'PASS' &&
    passA.rescore.result.validForH2Claim === true,
  passA.rescore.result,
);

const comparisonTamper = buildH2ExperimentReceipt('pass');
comparisonTamper.comparisons.cBeatsA1CiLow = 999;
comparisonTamper.comparisons.superAdditiveCiLow = -999;
const comparisonRescore = rescoreH2ExperimentReceipt(comparisonTamper);
record(
  'independent rescore ignores caller-supplied comparison fields and recomputes them from raw traces',
  comparisonRescore.result.verdict === 'PASS' &&
    comparisonRescore.receipt.comparisons.superAdditiveCiLow !== -999 &&
    hasMismatch(comparisonRescore, 'comparisons') &&
    comparisonRescore.experimentReceiptHash.valid === false,
  comparisonRescore,
);

const rawTamper = buildH2ExperimentReceipt('pass');
for (const seedRun of rawTamper.experiment.rawArms.C) {
  for (const point of seedRun.points) point.resolve = Number((0.2 + point.g * 0.01).toFixed(4));
}
const rawTamperRescore = rescoreH2ExperimentReceipt(rawTamper);
record(
  'raw trace tamper changes the independent verdict and invalidates the experiment receipt hash',
  rawTamperRescore.result.verdict === 'NULL' &&
    hasCode(rawTamperRescore.result.nullReasons, 'PASS_BAR_B1_FAILED') &&
    hasMismatch(rawTamperRescore, 'arms') &&
    rawTamperRescore.experimentReceiptHash.valid === false,
  rawTamperRescore,
);

const nullRun = runH2Experiment('null-coupling');
record(
  'non-degenerate raw traces without coupled super-additivity rescore to NULL',
  nullRun.rescore.result.verdict === 'NULL' &&
    nullRun.rescore.result.protocolFailures.length === 0 &&
    hasCode(nullRun.rescore.result.nullReasons, 'PASS_BAR_B2_FAILED'),
  nullRun.rescore.result,
);

const missingArm = runH2Experiment('missing-arm');
record(
  'missing required arm in raw traces is VOID, not NULL or PASS',
  missingArm.rescore.result.verdict === 'VOID' &&
    hasCode(missingArm.rescore.result.protocolFailures, 'ARM_DATA_MISSING'),
  missingArm.rescore.result,
);

const staleHash = runH2Experiment('tampered-hash');
record(
  'stale preregistration hash is VOID even when raw traces are otherwise PASS-shaped',
  staleHash.rescore.result.verdict === 'VOID' &&
    hasCode(staleHash.rescore.result.protocolFailures, 'PREREGISTRATION_HASH_MISMATCH'),
  staleHash.rescore.result,
);

const selfReported = runH2Experiment('self-reported-pass-null');
record(
  'self-reported PASS is ignored when raw-trace rescore is NULL',
  selfReported.receipt.selfReportedVerdict === 'PASS' &&
    selfReported.rescore.result.verdict === 'NULL' &&
    selfReported.rescore.result.selfReportedVerdictIgnored === true,
  selfReported.rescore.result,
);

const ok = results.every((result) => result.ok);
const payload = { ok, gate: 'h2-experiment-harness', results };
if (jsonMode) {
  process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
} else {
  for (const result of results) process.stdout.write(`${result.ok ? 'PASS' : 'FAIL'} ${result.name}\n`);
}
process.exit(ok ? 0 : 1);
