#!/usr/bin/env node
import {
  buildH2Fixture,
  computePreregistrationHash,
  evaluateH2Receipt,
  h2DefaultConfig,
} from '../h2-harness-runner.mjs';

const jsonMode = process.argv.includes('--json');
const results = [];

function record(name, ok, detail = {}) {
  results.push({ name, ok: Boolean(ok), detail });
}

function hasCode(entries, code) {
  return Array.isArray(entries) && entries.some((entry) => entry.code === code);
}

const passReceipt = buildH2Fixture('pass');
const pass = evaluateH2Receipt(passReceipt);
record('valid preregistered H2 receipt gets PASS and all B1-B7 bars are true',
  pass.verdict === 'PASS' && pass.validForH2Claim === true && Object.values(pass.passBars).every(Boolean),
  pass,
);
record('preregistration hash is a stable digest of the frozen config',
  passReceipt.preregistration_hash === computePreregistrationHash(passReceipt.config) &&
    computePreregistrationHash(h2DefaultConfig()) === computePreregistrationHash(h2DefaultConfig()),
  { expected: pass.preregistration.expectedHash, actual: pass.preregistration.actualHash },
);

const nullResult = evaluateH2Receipt(buildH2Fixture('null-coupling'));
record('non-VOID sound metric with no coupled super-additive effect is NULL, not PASS or VOID',
  nullResult.verdict === 'NULL' &&
    nullResult.protocolFailures.length === 0 &&
    hasCode(nullResult.nullReasons, 'PASS_BAR_B2_FAILED'),
  nullResult,
);

const degenerate = evaluateH2Receipt(buildH2Fixture('void-degenerate'));
record('degenerate resolution guard produces VOID before arm comparison',
  degenerate.verdict === 'VOID' && hasCode(degenerate.protocolFailures, 'DEGENERATION_GUARD'),
  degenerate,
);

const stale = evaluateH2Receipt(buildH2Fixture('stale-hash'));
record('stale preregistration hash produces VOID',
  stale.verdict === 'VOID' && hasCode(stale.protocolFailures, 'PREREGISTRATION_HASH_MISMATCH'),
  stale,
);

const scalar = evaluateH2Receipt(buildH2Fixture('scalar-metric'));
record('scalar resolve@K ranking is rejected as a VOID harness',
  scalar.verdict === 'VOID' && hasCode(scalar.protocolFailures, 'PRIMARY_METRIC_2D'),
  scalar,
);

const ablation = evaluateH2Receipt(buildH2Fixture('feature-ablation-survives'));
record('guide signal that survives proof-feature ablation is disqualified and cannot PASS',
  ablation.verdict === 'NULL' &&
    ablation.passBars.B4 === false &&
    hasCode(ablation.nullReasons, 'GUIDE_FEATURE_ABLATION_SURVIVES'),
  ablation,
);

const library = evaluateH2Receipt(buildH2Fixture('library-no-utility'));
record('library admission without held-out utility is VOID',
  library.verdict === 'VOID' && hasCode(library.protocolFailures, 'LIBRARY_ADMISSION_UTILITY'),
  library,
);

const selfReported = evaluateH2Receipt(buildH2Fixture('self-reported-pass-null'));
record('self-reported PASS is ignored by independent rescore',
  selfReported.verdict === 'NULL' && selfReported.selfReportedVerdict === 'PASS' && selfReported.selfReportedVerdictIgnored === true,
  selfReported,
);

const ok = results.every((result) => result.ok);
const payload = { ok, gate: 'h2-harness-runner', results };
if (jsonMode) {
  process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
} else {
  for (const result of results) process.stdout.write(`${result.ok ? 'PASS' : 'FAIL'} ${result.name}\n`);
}
process.exit(ok ? 0 : 1);
