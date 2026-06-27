#!/usr/bin/env node
import fs from 'node:fs';
import { pathToFileURL } from 'node:url';
import {
  buildH2Fixture,
  computePreregistrationHash,
  evaluateH2Receipt,
  h2DefaultConfig,
  sha256,
  stableJson,
} from './h2-harness-runner.mjs';

/** @typedef {{g: number, resolve: number}} H2Point */
/** @typedef {{seed: number, points: H2Point[]}} H2SeedSeries */
/** @typedef {{start: number, step: number}} ArmSpec */
/** @typedef {{points: H2Point[], seedSeries: H2SeedSeries[], slopeCiLow: number, slopeCiHigh: number, finalThirdGainCiLow: number}} H2ArmData */
/** @typedef {{arms: Record<string, H2ArmData>, comparisons: Record<string, number>, seedEvidence: {seedCount: number, individualPasses: number}}} DerivedH2Fields */

export const H2_EXPERIMENT_SCENARIOS = Object.freeze([
  'pass',
  'null-coupling',
  'void-degenerate',
  'feature-ablation-survives',
  'library-no-utility',
  'missing-arm',
  'tampered-hash',
  'self-reported-pass-null',
]);

const REQUIRED_ARMS = Object.freeze(['C', 'A1', 'A2', 'PERM']);
const DEFAULT_SEEDS = Object.freeze([101, 202, 303, 404, 505]);
const DEFAULT_ITERATIONS = 8;

/** @template T @param {T} value @returns {T} */
function clone(value) {
  return /** @type {T} */ (JSON.parse(JSON.stringify(value)));
}

/** @param {number} value @returns {number} */
function round4(value) {
  return Number(value.toFixed(4));
}

/** @param {number} value @param {number} min @param {number} max @returns {number} */
function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

/** @param {number[]} values @param {number} fallback @returns {number} */
function minOr(values, fallback) {
  return values.length > 0 ? Math.min(...values) : fallback;
}

/** @param {number[]} values @param {number} fallback @returns {number} */
function maxOr(values, fallback) {
  return values.length > 0 ? Math.max(...values) : fallback;
}

/** @param {number[]} values @param {number} [margin] @returns {number} */
function ciLow(values, margin = 0.005) {
  return round4(minOr(values, -1) - margin);
}

/** @param {number[]} values @param {number} [margin] @returns {number} */
function ciHigh(values, margin = 0.005) {
  return round4(maxOr(values, 1) + margin);
}

/** @param {H2Point[]} points @returns {number} */
function delta(points) {
  if (!Array.isArray(points) || points.length < 2) return Number.NaN;
  return round4(points[points.length - 1].resolve - points[0].resolve);
}

/** @param {H2Point[]} points @returns {number} */
function finalThirdGain(points) {
  if (!Array.isArray(points) || points.length < 3) return Number.NaN;
  const split = Math.max(0, Math.floor((points.length * 2) / 3) - 1);
  return round4(points[points.length - 1].resolve - points[split].resolve);
}

/** @param {string} scenario @returns {Record<string, ArmSpec>} */
function scenarioArmSpecs(scenario) {
  const specs = {
    C: { start: 0.2, step: 0.06 },
    A1: { start: 0.2, step: 0.02 },
    A2: { start: 0.2, step: 0.015 },
    PERM: { start: 0.2, step: 0.001 },
  };
  if (scenario === 'null-coupling' || scenario === 'self-reported-pass-null') {
    specs.C = { start: 0.2, step: 0.025 };
    specs.A1 = { start: 0.2, step: 0.02 };
    specs.A2 = { start: 0.2, step: 0.018 };
  }
  return specs;
}

/** @param {number} seed @param {ArmSpec} spec @param {number} iterations @returns {H2SeedSeries} */
function generateSeedSeries(seed, spec, iterations) {
  const seedOffset = ((seed % 17) - 8) * 0.0008;
  const points = [];
  for (let g = 0; g < iterations; g += 1) {
    const wobble = (((seed + g) % 3) - 1) * 0.0003;
    points.push({ g, resolve: round4(clamp(spec.start + spec.step * g + seedOffset + wobble, 0, 1)) });
  }
  return { seed, points };
}

/** @param {Record<string, ArmSpec>} specs @param {number[]} seeds @param {number} iterations @returns {Record<string, H2SeedSeries[]>} */
function buildRawArms(specs, seeds, iterations) {
  /** @type {Record<string, H2SeedSeries[]>} */
  const rawArms = {};
  for (const [armName, spec] of Object.entries(specs)) {
    rawArms[armName] = seeds.map((seed) => generateSeedSeries(seed, spec, iterations));
  }
  return rawArms;
}

/** @param {H2SeedSeries[]} seedSeries @returns {H2ArmData} */
function aggregateArm(seedSeries) {
  const series = Array.isArray(seedSeries) ? seedSeries : [];
  const width = series.length > 0 ? series[0].points.length : 0;
  const points = [];
  for (let g = 0; g < width; g += 1) {
    const values = series.map((seedRun) => seedRun.points[g]?.resolve).filter((value) => Number.isFinite(value));
    const mean = values.reduce((sum, value) => sum + value, 0) / Math.max(1, values.length);
    points.push({ g, resolve: round4(mean) });
  }
  const deltas = series.map((seedRun) => delta(seedRun.points)).filter((value) => Number.isFinite(value));
  const finalGains = series.map((seedRun) => finalThirdGain(seedRun.points)).filter((value) => Number.isFinite(value));
  return {
    points,
    seedSeries: clone(series),
    slopeCiLow: ciLow(deltas),
    slopeCiHigh: ciHigh(deltas),
    finalThirdGainCiLow: ciLow(finalGains),
  };
}

/** @param {H2SeedSeries[] | undefined} left @param {H2SeedSeries[] | undefined} right @returns {number[]} */
function pairedDeltaDiffs(left, right) {
  const a = Array.isArray(left) ? left : [];
  const b = Array.isArray(right) ? right : [];
  const count = Math.min(a.length, b.length);
  const values = [];
  for (let index = 0; index < count; index += 1) values.push(round4(delta(a[index].points) - delta(b[index].points)));
  return values.filter((value) => Number.isFinite(value));
}

/** @param {H2SeedSeries[] | undefined} c @param {H2SeedSeries[] | undefined} a1 @param {H2SeedSeries[] | undefined} a2 @returns {number[]} */
function pairedSuperAdditive(c, a1, a2) {
  const cRuns = Array.isArray(c) ? c : [];
  const a1Runs = Array.isArray(a1) ? a1 : [];
  const a2Runs = Array.isArray(a2) ? a2 : [];
  const count = Math.min(cRuns.length, a1Runs.length, a2Runs.length);
  const values = [];
  for (let index = 0; index < count; index += 1) {
    values.push(round4(delta(cRuns[index].points) - delta(a1Runs[index].points) - delta(a2Runs[index].points)));
  }
  return values.filter((value) => Number.isFinite(value));
}

/** @param {Record<string, H2SeedSeries[]>} rawArms @returns {{seedCount: number, individualPasses: number}} */
function seedEvidenceFromRaw(rawArms) {
  const count = Math.min(
    rawArms.C?.length ?? 0,
    rawArms.A1?.length ?? 0,
    rawArms.A2?.length ?? 0,
    rawArms.PERM?.length ?? 0,
  );
  let individualPasses = 0;
  for (let index = 0; index < count; index += 1) {
    const c = delta(rawArms.C[index].points);
    const a1 = delta(rawArms.A1[index].points);
    const a2 = delta(rawArms.A2[index].points);
    const perm = delta(rawArms.PERM[index].points);
    if (c - a1 > 0 && c - a2 > 0 && c - perm > 0 && c - a1 - a2 > 0.02) individualPasses += 1;
  }
  return { seedCount: rawArms.C?.length ?? 0, individualPasses };
}

/** @param {Record<string, H2SeedSeries[]>} rawArms @returns {DerivedH2Fields} */
export function deriveH2Fields(rawArms) {
  /** @type {Record<string, H2ArmData>} */
  const arms = {};
  for (const armName of Object.keys(rawArms ?? {})) {
    arms[armName] = aggregateArm(rawArms[armName]);
  }
  const comparisons = {
    cBeatsA1CiLow: ciLow(pairedDeltaDiffs(rawArms.C, rawArms.A1)),
    cBeatsA2CiLow: ciLow(pairedDeltaDiffs(rawArms.C, rawArms.A2)),
    cBeatsPermCiLow: ciLow(pairedDeltaDiffs(rawArms.C, rawArms.PERM)),
    superAdditiveCiLow: ciLow(pairedSuperAdditive(rawArms.C, rawArms.A1, rawArms.A2)),
  };
  return { arms, comparisons, seedEvidence: seedEvidenceFromRaw(rawArms) };
}

/** @param {Record<string, any>} receipt @returns {string} */
export function computeH2ExperimentReceiptHash(receipt) {
  const normalized = clone(receipt);
  delete normalized.experimentReceiptSha256;
  return sha256(stableJson(normalized));
}

/** @param {Record<string, any>} receipt @returns {Record<string, any>} */
export function finalizeH2ExperimentReceipt(receipt) {
  receipt.preregistration_hash = computePreregistrationHash(receipt.config);
  receipt.experimentReceiptSha256 = computeH2ExperimentReceiptHash(receipt);
  return receipt;
}

/** @param {string} [scenario] @returns {Record<string, any>} */
export function buildH2ExperimentReceipt(scenario = 'pass') {
  if (!H2_EXPERIMENT_SCENARIOS.includes(scenario)) throw new Error(`unknown H2 experiment scenario: ${scenario}`);
  const metricScenario = scenario === 'self-reported-pass-null' ? 'null-coupling' : scenario;
  const config = h2DefaultConfig();
  const seeds = [...DEFAULT_SEEDS];
  const rawArms = buildRawArms(scenarioArmSpecs(metricScenario), seeds, DEFAULT_ITERATIONS);
  if (scenario === 'missing-arm') delete rawArms.A2;

  /** @type {Record<string, any>} */
  const receipt = buildH2Fixture('pass');
  receipt.config = config;
  receipt.selfReportedVerdict = 'PASS';
  receipt.experiment = {
    schemaVersion: 1,
    scenario,
    seeds,
    iterations: DEFAULT_ITERATIONS,
    rawArms,
    derivedBy: 'h2-experiment-harness',
  };
  Object.assign(receipt, deriveH2Fields(rawArms));

  if (scenario === 'void-degenerate') {
    receipt.degenerationGuard.positiveResolve = 0.55;
    receipt.degenerationGuard.negativeResolve = 0.35;
    receipt.degenerationGuard.resolution = 0.2;
  } else if (scenario === 'feature-ablation-survives') {
    receipt.guideSignal.featureAblation.ablatedVsFrequencyPriorCiLow = 0.02;
    receipt.guideSignal.featureAblation.fullMinusAblatedCiLow = -0.01;
  } else if (scenario === 'library-no-utility') {
    receipt.libraryAdmission.medianSearchReduction = 0.02;
    receipt.libraryAdmission.resolveLiftCiLow = -0.01;
  }

  finalizeH2ExperimentReceipt(receipt);
  if (scenario === 'tampered-hash') receipt.preregistration_hash = `stale-${receipt.preregistration_hash.slice(0, 12)}`;
  return receipt;
}

/** @param {Record<string, any>} receipt @returns {{ok: boolean, result: Record<string, any>, receipt: Record<string, any>, fieldMismatches: string[], derivedFieldsRecomputed: boolean, experimentReceiptHash: {declared: string | null, actual: string, valid: boolean}}} */
export function rescoreH2ExperimentReceipt(receipt) {
  const source = receipt && typeof receipt === 'object' ? receipt : {};
  const rawArms = source.experiment && typeof source.experiment === 'object' && source.experiment.rawArms
    ? source.experiment.rawArms
    : {};
  const derived = deriveH2Fields(rawArms);
  const rescored = clone(source);
  rescored.arms = derived.arms;
  rescored.comparisons = derived.comparisons;
  rescored.seedEvidence = derived.seedEvidence;

  const fieldMismatches = [];
  if (stableJson(source.arms ?? {}) !== stableJson(derived.arms)) fieldMismatches.push('arms');
  if (stableJson(source.comparisons ?? {}) !== stableJson(derived.comparisons)) fieldMismatches.push('comparisons');
  if (stableJson(source.seedEvidence ?? {}) !== stableJson(derived.seedEvidence)) fieldMismatches.push('seedEvidence');

  const declared = typeof source.experimentReceiptSha256 === 'string' ? source.experimentReceiptSha256 : null;
  const actual = computeH2ExperimentReceiptHash(source);
  const result = evaluateH2Receipt(rescored);
  return {
    ok: result.ok === true,
    result,
    receipt: rescored,
    fieldMismatches,
    derivedFieldsRecomputed: true,
    experimentReceiptHash: { declared, actual, valid: declared === actual },
  };
}

/** @param {string} [scenario] @returns {{ok: boolean, scenario: string, receipt: Record<string, any>, rescore: ReturnType<typeof rescoreH2ExperimentReceipt>}} */
export function runH2Experiment(scenario = 'pass') {
  const receipt = buildH2ExperimentReceipt(scenario);
  return { ok: true, scenario, receipt, rescore: rescoreH2ExperimentReceipt(receipt) };
}

async function main() {
  const jsonMode = process.argv.includes('--json');
  const scenarioArg = process.argv.find((arg) => arg.startsWith('--scenario='));
  const stdinMode = process.argv.includes('--stdin');
  const scenario = scenarioArg ? scenarioArg.slice('--scenario='.length) : 'pass';
  const receipt = stdinMode ? JSON.parse(fs.readFileSync(0, 'utf8')) : buildH2ExperimentReceipt(scenario);
  const rescore = rescoreH2ExperimentReceipt(receipt);
  const payload = { ok: true, gate: 'h2-experiment-harness', scenario, receipt, rescore };
  process.stdout.write(jsonMode ? `${JSON.stringify(payload, null, 2)}\n` : `${rescore.result.verdict}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`${error && error.stack ? error.stack : error}\n`);
    process.exit(1);
  });
}
