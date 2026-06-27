#!/usr/bin/env node
'use strict';

const jsonMode = process.argv.includes('--json');

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function includesAll(values, required) {
  return Array.isArray(values) && required.every((value) => values.includes(value));
}

function exactSet(values, required) {
  return Array.isArray(values) && values.length === required.length && includesAll(values, required);
}

function failUnless(failures, code, ok, detail) {
  if (!ok) failures.push({ code, detail });
}

const REQUIRED_FROZEN_FIELDS = [
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
];

const REQUIRED_SHORTCUT_HYPOTHESES = ['P1', 'P2', 'P3'];
const REQUIRED_Z3_STATUSES = ['EQUIV', 'NOT_EQUIV', 'UNKNOWN'];
const REQUIRED_ARMS = ['C', 'A1', 'A2', 'PERM'];
const REQUIRED_GUIDE_COMPARISONS = [
  'ranking-permuted',
  'random-frozen-guide',
  'frequency-prior',
];
const REQUIRED_CURVES = ['raw-db', 'utility-gated-db'];
const REQUIRED_PASS_BARS = ['B1', 'B2', 'B3', 'B4', 'B5', 'B6', 'B7'];
const VERDICTS = ['PASS', 'NULL', 'VOID'];

const VALID_CONTRACT = {
  gate: 'h2-harness-contract',
  claims: {
    currentResultVerdict: 'VOID',
    hasIndependentRescoreReceipt: false,
    cvc5Status: 'pending',
    noPassClaimWithoutReceipt: true,
    reportVoidNullPassExplicitly: true,
  },
  preregistration: {
    required: true,
    hashField: 'preregistration_hash',
    freezeBeforeRun: true,
    minSeeds: 5,
    splitBy: 'novel_family',
    frozenFields: REQUIRED_FROZEN_FIELDS,
    postResultTuningAllowed: false,
    freshHashOnConfigChange: true,
    priorResultBecomesExploratoryOnConfigChange: true,
    nullMustBeReportedAsNull: true,
    everyGateRunsInRun: true,
  },
  shortcut: {
    metric: 'resolve@K',
    shortcutAllowedOnlyWhen: REQUIRED_SHORTCUT_HYPOTHESES,
    fallbackWhenAnyHypothesisMissing: 'full-z3-all-arms',
    P1: {
      enumerationComplete: true,
      capped: false,
      opndCapRateMax: 0,
      emitsDomainCardinality: true,
      depth2VsDepth1Tripwire: true,
    },
    P2: {
      usesZ3CollisionAudit: true,
      collisionRateMax: 0.01,
      disagreementsMax: 0,
      notEquivInvalidatesShortcut: true,
    },
    P3: {
      expressible2Required: true,
      falseRoutesTo: 'F4-residue',
      unknownRoutesTo: 'full-z3',
      frozenBaseGrammar: true,
    },
    dualPolaritySelfCheck: {
      outerOpInTopKReturnsOne: true,
      outerOpRemovedReturnsZero: true,
      failureVoidsHarness: true,
    },
  },
  z3SoundnessAudit: {
    separateFromMetricLoop: true,
    samplesDistinctPairsWithSameSignature: true,
    signatureProbeCount: 42,
    sampleSize: 1000,
    orAllPairs: true,
    statuses: REQUIRED_Z3_STATUSES,
    collisionRateMax: 0.01,
    disagreementsMax: 0,
    unknownRateMax: 0.02,
    anyNotEquivInvalidatesShortcut: true,
    collisionTrendVsGenerationPlotted: true,
    correlatedResolveRiseVoidsHarness: true,
  },
  degenerationGuard: {
    positiveControlVariantsMin: 20,
    negativeControlVariantsMin: 20,
    positiveResolveMin: 0.95,
    negativeResolveMax: 0.05,
    resolutionMin: 0.9,
    requiredBeforeAnyArmComparison: true,
    voidWhenBelowResolution: true,
    nullRequiresNonVoidInstrument: true,
    verdicts: VERDICTS,
  },
  primaryMetric: {
    name: 'novel_family_resolve@K',
    dimensions: ['g', 'resolve'],
    slopeOverGeneration: true,
    fixedK: true,
    fixedGuideCheckpoint: true,
    scalarRankingOnly: false,
    interactionStatistic: 'delta_coupled_minus_delta_guide_minus_delta_library',
    superAdditiveMarginPreregistered: true,
    permutationControlRequired: true,
    armsMustBeatBothAblations: true,
  },
  arms: {
    minSeeds: 5,
    heldoutByNovelFamily: true,
    noProblemStatementLeakage: true,
    leakageProbeAtChanceRequired: true,
    names: REQUIRED_ARMS,
    definitions: {
      C: 'live-guide-growing-library',
      A1: 'frozen-or-random-guide-growing-library',
      A2: 'live-guide-frozen-grammar',
      PERM: 'permuted-labels',
    },
  },
  guideSignal: {
    baseline: 'frequency-prior',
    comparisons: REQUIRED_GUIDE_COMPARISONS,
    confidenceIntervalsSeparate: true,
    featureAblation: {
      removesProofDerivedFeatures: true,
      proofDerivedSignalMustDropUnderAblation: true,
      disqualifyGuideIfSignalSurvivesAblation: true,
    },
  },
  libraryAdmission: {
    z3EquivalenceUniversal: true,
    heldoutUtilityRequired: true,
    utilityCriteria: {
      medianSearchReductionMin: 0.1,
      orResolveLiftCiExcludesZero: true,
    },
    nonRegressionInvariant: true,
    reportCurves: REQUIRED_CURVES,
    citeOnlyUtilityGatedCurve: true,
  },
  passBars: {
    minIterations: 8,
    minSeeds: 5,
    harnessNonVoidRequired: true,
    allRequired: REQUIRED_PASS_BARS,
    definitions: {
      B1: { required: true, slopeCiExcludesZero: true, finalMinusFirstMin: 0.15 },
      B2: { required: true, beatsA1: true, beatsA2: true, separateCi: true },
      B3: { required: true, permutedFlat: true, coupledBeatsPermuted: true },
      B4: { required: true, guideSignalReal: true },
      B5: { required: true, individualSeedPassesMin: 4, seedCount: 5 },
      B6: { required: true, recursivePrimitiveUsed: true, abstractionDepthMin: 2, heldoutUsesRecursivePrimitive: true },
      B7: { required: true, finalThirdGainPositive: true, ciExcludesZero: true },
    },
    nullRule: {
      harnessNonVoidRequired: true,
      metricSoundRequired: true,
      coupledMustBeatBothAblations: true,
      slopeCiIncludesZeroMayBeNull: true,
      coupledApproxPermutedMayBeNull: true,
    },
  },
  independentRescore: {
    required: true,
    fromPreregistrationHash: true,
    frozenIndependentScript: true,
    selfReportedH2RejectedWithoutRescore: true,
    workflowAfterVerdict: ['rescore', 'H3-explore'],
  },
};

function evaluateHarnessContract(contract) {
  const failures = [];
  const claims = contract.claims ?? {};
  const prereg = contract.preregistration ?? {};
  const shortcut = contract.shortcut ?? {};
  const p1 = shortcut.P1 ?? {};
  const p2 = shortcut.P2 ?? {};
  const p3 = shortcut.P3 ?? {};
  const polarity = shortcut.dualPolaritySelfCheck ?? {};
  const z3 = contract.z3SoundnessAudit ?? {};
  const guard = contract.degenerationGuard ?? {};
  const metric = contract.primaryMetric ?? {};
  const arms = contract.arms ?? {};
  const guide = contract.guideSignal ?? {};
  const ablation = guide.featureAblation ?? {};
  const library = contract.libraryAdmission ?? {};
  const utility = library.utilityCriteria ?? {};
  const passBars = contract.passBars ?? {};
  const bars = passBars.definitions ?? {};
  const nullRule = passBars.nullRule ?? {};
  const rescore = contract.independentRescore ?? {};

  failUnless(failures, 'CLAIM_VERDICT_TRICHOTOMY', VERDICTS.includes(claims.currentResultVerdict), claims);
  failUnless(failures, 'CLAIM_NON_CLAIM_RECEIPT', claims.currentResultVerdict === 'VOID' || claims.hasIndependentRescoreReceipt === true, claims);
  failUnless(failures, 'CLAIM_NO_PASS_WITHOUT_RECEIPT', claims.currentResultVerdict !== 'PASS' || claims.hasIndependentRescoreReceipt === true, claims);
  failUnless(failures, 'CLAIM_CVC5_HONESTY', claims.cvc5Status === 'pending' || claims.cvc5Status === 'installed-and-wired', claims);
  failUnless(failures, 'CLAIM_REPORTS_TRICHOTOMY', claims.reportVoidNullPassExplicitly === true, claims);

  failUnless(failures, 'PREREG_REQUIRED', prereg.required === true && prereg.freezeBeforeRun === true, prereg);
  failUnless(failures, 'PREREG_HASH', prereg.hashField === 'preregistration_hash', prereg);
  failUnless(failures, 'PREREG_MIN_SEEDS', prereg.minSeeds >= 5, prereg);
  failUnless(failures, 'PREREG_SPLIT', prereg.splitBy === 'novel_family', prereg);
  failUnless(failures, 'PREREG_FROZEN_FIELDS', includesAll(prereg.frozenFields, REQUIRED_FROZEN_FIELDS), prereg.frozenFields);
  failUnless(failures, 'POST_RESULT_TUNING', prereg.postResultTuningAllowed === false, prereg);
  failUnless(failures, 'PREREG_HASH_CHANGE_VOIDS_PRIOR', prereg.freshHashOnConfigChange === true && prereg.priorResultBecomesExploratoryOnConfigChange === true, prereg);
  failUnless(failures, 'PREREG_NULL_HONESTY', prereg.nullMustBeReportedAsNull === true && prereg.everyGateRunsInRun === true, prereg);

  failUnless(failures, 'SHORTCUT_HYPOTHESES', exactSet(shortcut.shortcutAllowedOnlyWhen, REQUIRED_SHORTCUT_HYPOTHESES), shortcut);
  failUnless(failures, 'SHORTCUT_FALLBACK', shortcut.fallbackWhenAnyHypothesisMissing === 'full-z3-all-arms', shortcut);
  failUnless(failures, 'SHORTCUT_P1_ENUMERATION', p1.enumerationComplete === true && p1.capped === false && p1.opndCapRateMax === 0 && p1.emitsDomainCardinality === true, p1);
  failUnless(failures, 'SHORTCUT_P1_TRIPWIRE', p1.depth2VsDepth1Tripwire === true, p1);
  failUnless(failures, 'SHORTCUT_P2_Z3_AUDIT', p2.usesZ3CollisionAudit === true && p2.collisionRateMax <= 0.01 && p2.disagreementsMax === 0 && p2.notEquivInvalidatesShortcut === true, p2);
  failUnless(failures, 'SHORTCUT_P3_EXPRESSIBLE', p3.expressible2Required === true && p3.falseRoutesTo === 'F4-residue' && p3.unknownRoutesTo === 'full-z3' && p3.frozenBaseGrammar === true, p3);
  failUnless(failures, 'SHORTCUT_DUAL_POLARITY', polarity.outerOpInTopKReturnsOne === true && polarity.outerOpRemovedReturnsZero === true && polarity.failureVoidsHarness === true, polarity);

  failUnless(failures, 'Z3_AUDIT_SEPARATE', z3.separateFromMetricLoop === true, z3);
  failUnless(failures, 'Z3_AUDIT_SAMPLING', z3.samplesDistinctPairsWithSameSignature === true && z3.signatureProbeCount === 42 && (z3.sampleSize >= 1000 || z3.orAllPairs === true), z3);
  failUnless(failures, 'Z3_AUDIT_STATUSES', exactSet(z3.statuses, REQUIRED_Z3_STATUSES), z3.statuses);
  failUnless(failures, 'Z3_AUDIT_THRESHOLDS', z3.collisionRateMax <= 0.01 && z3.disagreementsMax === 0 && z3.unknownRateMax <= 0.02, z3);
  failUnless(failures, 'Z3_AUDIT_NOT_EQUIV_INVALIDATES', z3.anyNotEquivInvalidatesShortcut === true, z3);
  failUnless(failures, 'Z3_AUDIT_COLLISION_TREND', z3.collisionTrendVsGenerationPlotted === true && z3.correlatedResolveRiseVoidsHarness === true, z3);

  failUnless(failures, 'DEGENERATION_CONTROLS', guard.positiveControlVariantsMin >= 20 && guard.negativeControlVariantsMin >= 20, guard);
  failUnless(failures, 'DEGENERATION_THRESHOLDS', guard.positiveResolveMin >= 0.95 && guard.negativeResolveMax <= 0.05 && guard.resolutionMin >= 0.9, guard);
  failUnless(failures, 'DEGENERATION_PRECEDES_COMPARISON', guard.requiredBeforeAnyArmComparison === true, guard);
  failUnless(failures, 'DEGENERATION_TRICHOTOMY', exactSet(guard.verdicts, VERDICTS) && guard.voidWhenBelowResolution === true && guard.nullRequiresNonVoidInstrument === true, guard);

  failUnless(failures, 'PRIMARY_METRIC_2D', metric.name === 'novel_family_resolve@K' && includesAll(metric.dimensions, ['g', 'resolve']) && metric.slopeOverGeneration === true, metric);
  failUnless(failures, 'PRIMARY_METRIC_FIXED_CONTEXT', metric.fixedK === true && metric.fixedGuideCheckpoint === true && metric.scalarRankingOnly === false, metric);
  failUnless(failures, 'PRIMARY_METRIC_INTERACTION', metric.interactionStatistic === 'delta_coupled_minus_delta_guide_minus_delta_library' && metric.superAdditiveMarginPreregistered === true, metric);
  failUnless(failures, 'ABLATIONS_REQUIRED', metric.armsMustBeatBothAblations === true && metric.permutationControlRequired === true && exactSet(arms.names, REQUIRED_ARMS), { metric, arms });
  failUnless(failures, 'ARMS_METHOD', arms.minSeeds >= 5 && arms.heldoutByNovelFamily === true && arms.noProblemStatementLeakage === true && arms.leakageProbeAtChanceRequired === true, arms);

  failUnless(failures, 'GUIDE_FREQUENCY_PRIOR', guide.baseline === 'frequency-prior' && includesAll(guide.comparisons, REQUIRED_GUIDE_COMPARISONS), guide);
  failUnless(failures, 'GUIDE_CI_AND_ABLATION', guide.confidenceIntervalsSeparate === true && ablation.removesProofDerivedFeatures === true && ablation.proofDerivedSignalMustDropUnderAblation === true && ablation.disqualifyGuideIfSignalSurvivesAblation === true, guide);

  failUnless(failures, 'LIBRARY_Z3_EQUIVALENCE', library.z3EquivalenceUniversal === true, library);
  failUnless(failures, 'LIBRARY_UTILITY', library.heldoutUtilityRequired === true && (utility.medianSearchReductionMin >= 0.1 || utility.orResolveLiftCiExcludesZero === true), library);
  failUnless(failures, 'LIBRARY_NON_REGRESSION', library.nonRegressionInvariant === true, library);
  failUnless(failures, 'LIBRARY_CURVES', includesAll(library.reportCurves, REQUIRED_CURVES) && library.citeOnlyUtilityGatedCurve === true, library);

  failUnless(failures, 'PASS_BARS_SCOPE', passBars.minIterations >= 8 && passBars.minSeeds >= 5 && passBars.harnessNonVoidRequired === true, passBars);
  failUnless(failures, 'PASS_BARS_ALL_REQUIRED', exactSet(passBars.allRequired, REQUIRED_PASS_BARS) && REQUIRED_PASS_BARS.every((bar) => bars[bar]?.required === true), passBars);
  failUnless(failures, 'PASS_B1_SLOPE', bars.B1?.slopeCiExcludesZero === true && bars.B1?.finalMinusFirstMin >= 0.15, bars.B1);
  failUnless(failures, 'PASS_B2_ABLATIONS', bars.B2?.beatsA1 === true && bars.B2?.beatsA2 === true && bars.B2?.separateCi === true, bars.B2);
  failUnless(failures, 'PASS_B3_PERMUTED', bars.B3?.permutedFlat === true && bars.B3?.coupledBeatsPermuted === true, bars.B3);
  failUnless(failures, 'PASS_B4_GUIDE', bars.B4?.guideSignalReal === true, bars.B4);
  failUnless(failures, 'PASS_B5_SEEDS', bars.B5?.individualSeedPassesMin >= 4 && bars.B5?.seedCount >= 5, bars.B5);
  failUnless(failures, 'PASS_B6_RECURSION', bars.B6?.recursivePrimitiveUsed === true && bars.B6?.abstractionDepthMin >= 2 && bars.B6?.heldoutUsesRecursivePrimitive === true, bars.B6);
  failUnless(failures, 'PASS_B7_NO_PLATEAU', bars.B7?.finalThirdGainPositive === true && bars.B7?.ciExcludesZero === true, bars.B7);
  failUnless(failures, 'NULL_RULE', nullRule.harnessNonVoidRequired === true && nullRule.metricSoundRequired === true && nullRule.coupledMustBeatBothAblations === true && nullRule.slopeCiIncludesZeroMayBeNull === true && nullRule.coupledApproxPermutedMayBeNull === true, nullRule);

  failUnless(failures, 'INDEPENDENT_RESCORE', rescore.required === true && rescore.fromPreregistrationHash === true && rescore.frozenIndependentScript === true && rescore.selfReportedH2RejectedWithoutRescore === true, rescore);
  failUnless(failures, 'POST_VERDICT_WORKFLOW', includesAll(rescore.workflowAfterVerdict, ['rescore', 'H3-explore']), rescore.workflowAfterVerdict);

  return { ok: failures.length === 0, failures };
}

function negativeControl(name, expectedCode, mutate) {
  const contract = clone(VALID_CONTRACT);
  mutate(contract);
  const result = evaluateHarnessContract(contract);
  return {
    name,
    expectedCode,
    ok: !result.ok && result.failures.some((failure) => failure.code === expectedCode),
    failureCodes: result.failures.map((failure) => failure.code),
  };
}

const primary = evaluateHarnessContract(VALID_CONTRACT);
const negativeControls = [
  negativeControl('missing preregistration hash is rejected', 'PREREG_HASH', (contract) => {
    delete contract.preregistration.hashField;
  }),
  negativeControl('post-result tuning is rejected', 'POST_RESULT_TUNING', (contract) => {
    contract.preregistration.postResultTuningAllowed = true;
  }),
  negativeControl('scalar-only resolve ranking is rejected', 'PRIMARY_METRIC_2D', (contract) => {
    contract.primaryMetric.name = 'resolve@K';
    contract.primaryMetric.dimensions = ['resolve'];
    contract.primaryMetric.slopeOverGeneration = false;
    contract.primaryMetric.scalarRankingOnly = true;
  }),
  negativeControl('coupled-only experiment without ablations is rejected', 'ABLATIONS_REQUIRED', (contract) => {
    contract.primaryMetric.armsMustBeatBothAblations = false;
    contract.primaryMetric.permutationControlRequired = false;
    contract.arms.names = ['C'];
  }),
  negativeControl('neural guide without frequency prior baseline is rejected', 'GUIDE_FREQUENCY_PRIOR', (contract) => {
    contract.guideSignal.baseline = 'uniform';
    contract.guideSignal.comparisons = ['ranking-permuted', 'random-frozen-guide'];
  }),
  negativeControl('feature-ablation survival is rejected as prior leakage', 'GUIDE_CI_AND_ABLATION', (contract) => {
    contract.guideSignal.featureAblation.proofDerivedSignalMustDropUnderAblation = false;
    contract.guideSignal.featureAblation.disqualifyGuideIfSignalSurvivesAblation = false;
  }),
  negativeControl('library admission without held-out utility is rejected', 'LIBRARY_UTILITY', (contract) => {
    contract.libraryAdmission.heldoutUtilityRequired = false;
    contract.libraryAdmission.utilityCriteria.medianSearchReductionMin = 0;
    contract.libraryAdmission.utilityCriteria.orResolveLiftCiExcludesZero = false;
  }),
  negativeControl('PASS claim without independent rescore receipt is rejected', 'CLAIM_NO_PASS_WITHOUT_RECEIPT', (contract) => {
    contract.claims.currentResultVerdict = 'PASS';
    contract.claims.hasIndependentRescoreReceipt = false;
  }),
  negativeControl('VOID instrument cannot be reported as NULL', 'DEGENERATION_THRESHOLDS', (contract) => {
    contract.claims.currentResultVerdict = 'NULL';
    contract.claims.hasIndependentRescoreReceipt = true;
    contract.degenerationGuard.positiveResolveMin = 0.4;
    contract.degenerationGuard.negativeResolveMax = 0.35;
    contract.degenerationGuard.resolutionMin = 0.1;
  }),
];

const ok = primary.ok && negativeControls.every((control) => control.ok);
const failures = [
  ...primary.failures.map((failure) => ({ scope: 'contract', ...failure })),
  ...negativeControls
    .filter((control) => !control.ok)
    .map((control) => ({ scope: 'negative-control', name: control.name, expectedCode: control.expectedCode, failureCodes: control.failureCodes })),
];

const payload = {
  ok,
  gate: 'h2-harness-contract',
  assertion: {
    currentH2Verdict: VALID_CONTRACT.claims.currentResultVerdict,
    cvc5Status: VALID_CONTRACT.claims.cvc5Status,
    contractIsMachineReadable: primary.ok,
    negativeControlsDiscriminating: negativeControls.every((control) => control.ok),
    doesNotClaimExperimentPassed: true,
  },
  failures,
  negativeControls,
};

if (jsonMode) {
  process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
} else {
  process.stdout.write(`${ok ? 'PASS' : 'FAIL'} h2-harness-contract\n`);
  for (const failure of failures) process.stdout.write(`${JSON.stringify(failure)}\n`);
}

process.exit(ok ? 0 : 1);
