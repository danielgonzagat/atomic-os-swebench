#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import { pathToFileURL } from 'node:url';

export const H2_VERDICTS = Object.freeze(['PASS', 'NULL', 'VOID']);
export const REQUIRED_H2_ARMS = Object.freeze(['C', 'A1', 'A2', 'PERM']);
export const REQUIRED_H2_FROZEN_FIELDS = Object.freeze([
  'K-sweep',
  'tau_res',
  'tau_collision',
  'margins',
  'seeds',
  'trainHeldoutSplitByNovelFamily',
  'featureSet',
  'probeSet',
  'operandDomain',
  'verdictRule',
  'interactionStatistic',
]);

export function stableValue(value) {
  if (Array.isArray(value)) return value.map(stableValue);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stableValue(value[key])]));
  }
  return value;
}

export function stableJson(value) {
  return JSON.stringify(stableValue(value));
}

export function sha256(text) {
  return crypto.createHash('sha256').update(text).digest('hex');
}

export function h2DefaultConfig() {
  return {
    schemaVersion: 1,
    K: 5,
    kSweep: [3, 5, 8],
    tau_res: 0.9,
    tau_collision: 0.01,
    maxUnknownRate: 0.02,
    minSeeds: 5,
    minIterations: 8,
    minAbsoluteGain: 0.15,
    interactionMargin: 0.02,
    maxPermutedSlopeCiHigh: 0.02,
    minMedianSearchReduction: 0.1,
    postResultTuningAllowed: false,
    splitBy: 'novel_family',
    frozenFields: [...REQUIRED_H2_FROZEN_FIELDS],
    metric: {
      name: 'novel_family_resolve@K',
      dimensions: ['g', 'resolve'],
      slopeOverGeneration: true,
      fixedK: true,
      fixedGuideCheckpoint: true,
      scalarRankingOnly: false,
    },
  };
}

export function computePreregistrationHash(config) {
  return sha256(stableJson(config));
}

function num(value, fallback = Number.NaN) {
  return Number.isFinite(Number(value)) ? Number(value) : fallback;
}

function hasAll(values, required) {
  return Array.isArray(values) && required.every((value) => values.includes(value));
}

function pushUnique(list, code, detail = undefined) {
  if (!list.some((entry) => entry.code === code)) list.push({ code, detail });
}

function pointsDelta(points) {
  if (!Array.isArray(points) || points.length < 2) return Number.NaN;
  return num(points[points.length - 1]?.resolve) - num(points[0]?.resolve);
}

function pointsFinal(points) {
  if (!Array.isArray(points) || points.length === 0) return Number.NaN;
  return num(points[points.length - 1]?.resolve);
}

function validateConfig(config, protocolFailures) {
  const metric = config.metric ?? {};
  if (config.postResultTuningAllowed !== false) pushUnique(protocolFailures, 'POST_RESULT_TUNING_ALLOWED');
  if (config.splitBy !== 'novel_family') pushUnique(protocolFailures, 'SPLIT_NOT_BY_NOVEL_FAMILY');
  if (!hasAll(config.frozenFields, REQUIRED_H2_FROZEN_FIELDS)) pushUnique(protocolFailures, 'PREREGISTRATION_FIELDS_INCOMPLETE');
  if (num(config.minSeeds, 0) < 5) pushUnique(protocolFailures, 'SEED_COUNT_TOO_LOW');
  if (num(config.minIterations, 0) < 8) pushUnique(protocolFailures, 'ITERATION_COUNT_TOO_LOW');
  if (
    metric.name !== 'novel_family_resolve@K' ||
    !hasAll(metric.dimensions, ['g', 'resolve']) ||
    metric.slopeOverGeneration !== true ||
    metric.fixedK !== true ||
    metric.fixedGuideCheckpoint !== true ||
    metric.scalarRankingOnly !== false
  ) {
    pushUnique(protocolFailures, 'PRIMARY_METRIC_2D');
  }
}

function validateDegeneration(receipt, config, protocolFailures) {
  const guard = receipt.degenerationGuard ?? {};
  const positive = num(guard.positiveResolve);
  const negative = num(guard.negativeResolve);
  const resolution = Number.isFinite(num(guard.resolution)) ? num(guard.resolution) : positive - negative;
  const ok =
    num(guard.positiveControlVariants, 0) >= 20 &&
    num(guard.negativeControlVariants, 0) >= 20 &&
    positive >= 0.95 &&
    negative <= 0.05 &&
    resolution >= num(config.tau_res, 0.9);
  if (!ok) pushUnique(protocolFailures, 'DEGENERATION_GUARD', { positive, negative, resolution });
}

function validateZ3(receipt, config, protocolFailures) {
  const audit = receipt.z3SoundnessAudit ?? {};
  const statuses = audit.statuses ?? [];
  const ok =
    audit.separateFromMetricLoop === true &&
    audit.samplesDistinctPairsWithSameSignature === true &&
    num(audit.signatureProbeCount) === 42 &&
    (num(audit.sampleSize, 0) >= 1000 || audit.orAllPairs === true) &&
    hasAll(statuses, ['EQUIV', 'NOT_EQUIV', 'UNKNOWN']) &&
    num(audit.collisionRate, 1) <= num(config.tau_collision, 0.01) &&
    num(audit.disagreements, 1) === 0 &&
    num(audit.unknownRate, 1) <= num(config.maxUnknownRate, 0.02) &&
    num(audit.notEquivCount, 1) === 0 &&
    audit.collisionResolveCorrelation === false;
  if (!ok) pushUnique(protocolFailures, 'Z3_SOUNDNESS_AUDIT');
}

function validateShortcut(receipt, protocolFailures) {
  const shortcut = receipt.shortcutAudit ?? {};
  const p1 = shortcut.P1 ?? {};
  const p2 = shortcut.P2 ?? {};
  const p3 = shortcut.P3 ?? {};
  const polarity = shortcut.dualPolaritySelfCheck ?? {};
  const ok =
    p1.enumerationComplete === true &&
    p1.capped === false &&
    num(p1.opndCapRate, 1) === 0 &&
    p1.emitsDomainCardinality === true &&
    p2.usesZ3CollisionAudit === true &&
    p2.notEquivInvalidatesShortcut === true &&
    p3.expressible2Required === true &&
    p3.falseRoutesTo === 'F4-residue' &&
    p3.unknownRoutesTo === 'full-z3' &&
    p3.frozenBaseGrammar === true &&
    polarity.outerOpInTopKReturnsOne === true &&
    polarity.outerOpRemovedReturnsZero === true &&
    polarity.failureVoidsHarness === true;
  if (!ok) pushUnique(protocolFailures, 'SHORTCUT_SOUNDNESS');
}

function validateArms(receipt, config, protocolFailures) {
  const arms = receipt.arms ?? {};
  const missing = REQUIRED_H2_ARMS.filter((arm) => !arms[arm]);
  if (missing.length > 0) {
    pushUnique(protocolFailures, 'ARM_DATA_MISSING', { missing });
    return;
  }
  const minIterations = num(config.minIterations, 8);
  for (const armName of REQUIRED_H2_ARMS) {
    const points = arms[armName]?.points;
    if (!Array.isArray(points) || points.length < minIterations) {
      pushUnique(protocolFailures, 'ARM_POINTS_INCOMPLETE', { arm: armName, count: Array.isArray(points) ? points.length : 0 });
    }
  }
}

function validateLibraryAdmission(receipt, config, protocolFailures) {
  const library = receipt.libraryAdmission ?? {};
  const utilityOk =
    num(library.medianSearchReduction, 0) >= num(config.minMedianSearchReduction, 0.1) ||
    num(library.resolveLiftCiLow, -1) > 0;
  const ok =
    library.z3EquivalenceUniversal === true &&
    utilityOk &&
    library.nonRegression === true &&
    Array.isArray(library.reportCurves) &&
    hasAll(library.reportCurves, ['raw-db', 'utility-gated-db']) &&
    library.citeOnlyUtilityGatedCurve === true;
  if (!ok) pushUnique(protocolFailures, 'LIBRARY_ADMISSION_UTILITY');
}

export function evaluateH2Receipt(receipt) {
  const protocolFailures = [];
  const nullReasons = [];
  if (!receipt || typeof receipt !== 'object') {
    return { ok: false, verdict: 'VOID', protocolFailures: [{ code: 'RECEIPT_NOT_OBJECT' }], nullReasons: [], passBars: {}, validForH2Claim: false };
  }

  const config = receipt.config ?? {};
  const expectedHash = computePreregistrationHash(config);
  if (receipt.preregistration_hash !== expectedHash) {
    pushUnique(protocolFailures, 'PREREGISTRATION_HASH_MISMATCH', {
      expected: expectedHash,
      actual: receipt.preregistration_hash ?? null,
    });
  }

  validateConfig(config, protocolFailures);
  validateDegeneration(receipt, config, protocolFailures);
  validateZ3(receipt, config, protocolFailures);
  validateShortcut(receipt, protocolFailures);
  validateArms(receipt, config, protocolFailures);
  validateLibraryAdmission(receipt, config, protocolFailures);

  const arms = receipt.arms ?? {};
  const comparisons = receipt.comparisons ?? {};
  const guide = receipt.guideSignal ?? {};
  const ablation = guide.featureAblation ?? {};
  const library = receipt.libraryAdmission ?? {};

  const cDelta = pointsDelta(arms.C?.points);
  const passBars = {
    B1: num(arms.C?.slopeCiLow, -1) > 0 && cDelta >= num(config.minAbsoluteGain, 0.15),
    B2:
      num(comparisons.cBeatsA1CiLow, -1) > 0 &&
      num(comparisons.cBeatsA2CiLow, -1) > 0 &&
      num(comparisons.superAdditiveCiLow, -1) > num(config.interactionMargin, 0.02),
    B3: num(arms.PERM?.slopeCiHigh, 1) <= num(config.maxPermutedSlopeCiHigh, 0.02) && num(comparisons.cBeatsPermCiLow, -1) > 0,
    B4:
      num(guide.rankingPermutedCiLow, -1) > 0 &&
      num(guide.randomFrozenCiLow, -1) > 0 &&
      num(guide.frequencyPriorCiLow, -1) > 0 &&
      ablation.removesProofDerivedFeatures === true &&
      num(ablation.ablatedVsFrequencyPriorCiLow, 1) <= 0 &&
      num(ablation.fullMinusAblatedCiLow, -1) > 0,
    B5: num(receipt.seedEvidence?.individualPasses, 0) >= 4 && num(receipt.seedEvidence?.seedCount, 0) >= 5,
    B6:
      library.recursivePrimitiveUsed === true &&
      num(library.abstractionDepth, 0) >= 2 &&
      library.heldoutUsesRecursivePrimitive === true,
    B7: num(arms.C?.finalThirdGainCiLow, -1) > 0,
  };

  if (!(num(guide.frequencyPriorCiLow, -1) > 0)) pushUnique(nullReasons, 'GUIDE_DOES_NOT_BEAT_FREQUENCY_PRIOR');
  if (num(ablation.ablatedVsFrequencyPriorCiLow, 1) > 0) pushUnique(nullReasons, 'GUIDE_FEATURE_ABLATION_SURVIVES');
  for (const [bar, ok] of Object.entries(passBars)) {
    if (!ok) pushUnique(nullReasons, `PASS_BAR_${bar}_FAILED`);
  }

  const verdict = protocolFailures.length > 0
    ? 'VOID'
    : Object.values(passBars).every(Boolean)
      ? 'PASS'
      : 'NULL';

  return {
    ok: true,
    verdict,
    validForH2Claim: verdict === 'PASS',
    preregistration: {
      expectedHash,
      actualHash: receipt.preregistration_hash ?? null,
      hashMatches: receipt.preregistration_hash === expectedHash,
    },
    protocolFailures,
    nullReasons,
    passBars,
    metrics: {
      cDelta,
      cFinal: pointsFinal(arms.C?.points),
      a1Delta: pointsDelta(arms.A1?.points),
      a2Delta: pointsDelta(arms.A2?.points),
      permDelta: pointsDelta(arms.PERM?.points),
    },
    selfReportedVerdict: receipt.selfReportedVerdict ?? null,
    selfReportedVerdictIgnored: receipt.selfReportedVerdict !== undefined && receipt.selfReportedVerdict !== verdict,
  };
}

function points(start, step, count = 8) {
  return Array.from({ length: count }, (_, g) => ({ g, resolve: Number((start + step * g).toFixed(4)) }));
}

function finalizeReceipt(receipt) {
  receipt.preregistration_hash = computePreregistrationHash(receipt.config);
  return receipt;
}

export function buildH2Fixture(kind = 'pass') {
  const config = h2DefaultConfig();
  const receipt = {
    schemaVersion: 1,
    config,
    selfReportedVerdict: 'PASS',
    degenerationGuard: {
      positiveControlVariants: 24,
      negativeControlVariants: 24,
      positiveResolve: 0.97,
      negativeResolve: 0.02,
      resolution: 0.95,
    },
    z3SoundnessAudit: {
      separateFromMetricLoop: true,
      samplesDistinctPairsWithSameSignature: true,
      signatureProbeCount: 42,
      sampleSize: 1000,
      orAllPairs: true,
      statuses: ['EQUIV', 'NOT_EQUIV', 'UNKNOWN'],
      collisionRate: 0.002,
      disagreements: 0,
      unknownRate: 0.01,
      notEquivCount: 0,
      collisionResolveCorrelation: false,
    },
    shortcutAudit: {
      P1: { enumerationComplete: true, capped: false, opndCapRate: 0, emitsDomainCardinality: true },
      P2: { usesZ3CollisionAudit: true, notEquivInvalidatesShortcut: true },
      P3: { expressible2Required: true, falseRoutesTo: 'F4-residue', unknownRoutesTo: 'full-z3', frozenBaseGrammar: true },
      dualPolaritySelfCheck: { outerOpInTopKReturnsOne: true, outerOpRemovedReturnsZero: true, failureVoidsHarness: true },
    },
    arms: {
      C: { points: points(0.2, 0.06), slopeCiLow: 0.018, finalThirdGainCiLow: 0.015 },
      A1: { points: points(0.2, 0.02), slopeCiLow: 0.004, finalThirdGainCiLow: 0.003 },
      A2: { points: points(0.2, 0.015), slopeCiLow: 0.003, finalThirdGainCiLow: 0.002 },
      PERM: { points: points(0.2, 0.001), slopeCiLow: -0.001, slopeCiHigh: 0.004, finalThirdGainCiLow: -0.002 },
    },
    comparisons: {
      cBeatsA1CiLow: 0.09,
      cBeatsA2CiLow: 0.11,
      cBeatsPermCiLow: 0.17,
      superAdditiveCiLow: 0.04,
    },
    guideSignal: {
      rankingPermutedCiLow: 0.03,
      randomFrozenCiLow: 0.03,
      frequencyPriorCiLow: 0.02,
      featureAblation: {
        removesProofDerivedFeatures: true,
        ablatedVsFrequencyPriorCiLow: -0.006,
        fullMinusAblatedCiLow: 0.025,
      },
    },
    libraryAdmission: {
      z3EquivalenceUniversal: true,
      medianSearchReduction: 0.12,
      resolveLiftCiLow: 0.01,
      nonRegression: true,
      reportCurves: ['raw-db', 'utility-gated-db'],
      citeOnlyUtilityGatedCurve: true,
      recursivePrimitiveUsed: true,
      abstractionDepth: 2,
      heldoutUsesRecursivePrimitive: true,
    },
    seedEvidence: { seedCount: 5, individualPasses: 5 },
  };

  if (kind === 'null-coupling') {
    receipt.comparisons.cBeatsA1CiLow = -0.01;
    receipt.comparisons.superAdditiveCiLow = -0.02;
    receipt.seedEvidence.individualPasses = 3;
  } else if (kind === 'void-degenerate') {
    receipt.degenerationGuard.positiveResolve = 0.55;
    receipt.degenerationGuard.negativeResolve = 0.35;
    receipt.degenerationGuard.resolution = 0.2;
  } else if (kind === 'scalar-metric') {
    receipt.config.metric = { name: 'resolve@K', dimensions: ['resolve'], scalarRankingOnly: true };
  } else if (kind === 'feature-ablation-survives') {
    receipt.guideSignal.featureAblation.ablatedVsFrequencyPriorCiLow = 0.02;
    receipt.guideSignal.featureAblation.fullMinusAblatedCiLow = -0.01;
  } else if (kind === 'library-no-utility') {
    receipt.libraryAdmission.medianSearchReduction = 0.02;
    receipt.libraryAdmission.resolveLiftCiLow = -0.01;
  } else if (kind === 'self-reported-pass-null') {
    receipt.comparisons.cBeatsA1CiLow = -0.01;
    receipt.comparisons.superAdditiveCiLow = -0.02;
    receipt.selfReportedVerdict = 'PASS';
  }

  finalizeReceipt(receipt);
  if (kind === 'stale-hash') receipt.preregistration_hash = `stale-${receipt.preregistration_hash.slice(0, 12)}`;
  return receipt;
}

async function main() {
  const jsonMode = process.argv.includes('--json');
  const fixtureArg = process.argv.find((arg) => arg.startsWith('--fixture='));
  const fixture = fixtureArg ? fixtureArg.slice('--fixture='.length) : null;
  const input = fixture ? buildH2Fixture(fixture) : JSON.parse(fs.readFileSync(0, 'utf8'));
  const result = evaluateH2Receipt(input);
  const payload = { ok: true, gate: 'h2-harness-runner', result };
  process.stdout.write(jsonMode ? `${JSON.stringify(payload, null, 2)}\n` : `${result.verdict}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`${error && error.stack ? error.stack : error}\n`);
    process.exit(1);
  });
}
