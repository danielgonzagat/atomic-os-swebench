#!/usr/bin/env node
import fs from 'node:fs';
import { pathToFileURL } from 'node:url';
import { computeMetrics } from './disproof-corpus-harness.mjs';
import { aggregateArm, parseLedgerJsonl, verifyRunLedgerJsonl } from './experiment-harness.mjs';
import { buildH2Fixture, h2DefaultConfig } from './h2-harness-runner.mjs';
import {
  computeH2ExperimentReceiptHash,
  deriveH2Fields,
  finalizeH2ExperimentReceipt,
  rescoreH2ExperimentReceipt,
} from './h2-experiment-harness.mjs';

export const H2_LEDGER_BRIDGE_VERSION = 'h2-ledger-bridge-v1';
export const H2_LEDGER_REQUIRED_ARMS = Object.freeze(['C', 'A1', 'A2', 'PERM']);

/** @template T @param {T} value @returns {T} */
function clone(value) {
  return /** @type {T} */ (JSON.parse(JSON.stringify(value)));
}

/** @param {unknown} value @returns {value is Record<string, any>} */
function isRecord(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/** @param {unknown} value @param {number} fallback @returns {number} */
function asNumber(value, fallback = 0) {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

/** @param {unknown} value @returns {value is string} */
function nonEmptyString(value) {
  return typeof value === 'string' && value.length > 0;
}

/** @param {number} value @returns {number} */
function round4(value) {
  return Number(value.toFixed(4));
}

/** @param {string} code @param {Record<string, any>} detail @returns {{code: string, detail: Record<string, any>}} */
function bridgeFailure(code, detail = {}) {
  return { code, detail };
}

/** @param {{generation: number, verdict?: {decision?: string, wallKey?: string | null}, diffText?: string | null, publicScore?: number | null, shadowCount?: number, unjudged?: boolean}[]} records */
function ledgerRecordsToMetricsProposals(records) {
  return records.map((record) => ({
    generation: record.generation,
    admitted: record.verdict?.decision === 'promote',
    wallKey: record.verdict?.wallKey ?? undefined,
    diffText: record.diffText ?? undefined,
    publicScore: record.publicScore ?? undefined,
    shadowCount: record.shadowCount,
    unjudged: record.unjudged === true,
  }));
}

/** @param {number} value @param {number} scoreScale @returns {number} */
function normalizeResolve(value, scoreScale) {
  const scale = scoreScale > 0 ? scoreScale : 1;
  return round4(Math.min(1, Math.max(0, value / scale)));
}

/** @param {{ledgerText: string, sourceArm: string, scoreScale: number, sourceLabel?: string}} args */
function ledgerEntryToRawArm(args) {
  const ledgerText = String(args.ledgerText ?? '');
  const sourceArm = args.sourceArm;
  const verified = verifyRunLedgerJsonl(ledgerText);
  if (verified.ok !== true) {
    return {
      ok: false,
      failures: [bridgeFailure('H2_LEDGER_CHAIN_INVALID', { sourceArm, error: verified.error })],
      source: { sourceArm, sourceLabel: args.sourceLabel ?? null, chainOk: false },
    };
  }
  const aggregate = aggregateArm({ ledgerText, arm: sourceArm });
  if (aggregate.ok !== true) {
    return {
      ok: false,
      failures: [bridgeFailure('H2_LEDGER_SOURCE_ARM_EMPTY', { sourceArm, error: aggregate.error })],
      source: { sourceArm, sourceLabel: args.sourceLabel ?? null, chainOk: true, chainHead: verified.headRecordSha256 ?? null },
    };
  }
  const parsed = parseLedgerJsonl(ledgerText);
  if (parsed.ok !== true) {
    return {
      ok: false,
      failures: [bridgeFailure('H2_LEDGER_PARSE_FAILED', { sourceArm, error: parsed.error })],
      source: { sourceArm, sourceLabel: args.sourceLabel ?? null, chainOk: true, chainHead: verified.headRecordSha256 ?? null },
    };
  }
  const records = parsed.records.filter((record) => record.arm === sourceArm);
  const seeds = [...new Set(records.map((record) => record.seed))].sort();
  const seedSeries = [];
  const failures = [];
  for (const seed of seeds) {
    const seedRecords = records.filter((record) => record.seed === seed);
    const metrics = computeMetrics({ proposals: ledgerRecordsToMetricsProposals(seedRecords) });
    if (metrics.ok !== true) {
      failures.push(bridgeFailure('H2_LEDGER_METRICS_FAILED', { sourceArm, seed, error: metrics.error }));
      continue;
    }
    seedSeries.push({
      seed,
      points: metrics.perGeneration.map((row, index) => ({
        g: index,
        resolve: normalizeResolve(asNumber(row.m3Capability, 0), args.scoreScale),
      })),
    });
  }
  const pointCounts = seedSeries.map((series) => series.points.length);
  return {
    ok: failures.length === 0,
    failures,
    seedSeries,
    source: {
      sourceArm,
      sourceLabel: args.sourceLabel ?? null,
      chainOk: true,
      chainHead: verified.headRecordSha256 ?? null,
      recordCount: verified.recordCount ?? records.length,
      seedCount: seeds.length,
      minIterations: pointCounts.length > 0 ? Math.min(...pointCounts) : 0,
      maxIterations: pointCounts.length > 0 ? Math.max(...pointCounts) : 0,
    },
  };
}

/** @param {unknown[]} failures @param {string} code @param {Record<string, any>} detail */
function pushFailure(failures, code, detail = {}) {
  failures.push(bridgeFailure(code, detail));
}

/** @param {{armLedgers?: Record<string, any>, baseReceipt?: Record<string, any>, config?: Record<string, any>, scoreScale?: number, bridgeId?: string}} input */
export function buildH2LedgerBridgeReceipt(input = {}) {
  const config = clone(input.config ?? input.baseReceipt?.config ?? h2DefaultConfig());
  const scoreScale = asNumber(input.scoreScale, 1) > 0 ? asNumber(input.scoreScale, 1) : 1;
  const sourceFailures = [];
  const rawArms = {};
  const sourceLedgers = {};
  const baseReceiptProvided = isRecord(input.baseReceipt);
  if (!baseReceiptProvided) {
    pushFailure(sourceFailures, 'H2_LEDGER_CONTROL_RECEIPT_MISSING', {
      reason: 'ledger curves alone do not attest degeneration, Z3, shortcut, guide-signal, or library-admission controls',
    });
  }

  const armLedgers = isRecord(input.armLedgers) ? input.armLedgers : {};
  for (const h2Arm of H2_LEDGER_REQUIRED_ARMS) {
    const entry = armLedgers[h2Arm];
    if (!isRecord(entry)) {
      pushFailure(sourceFailures, 'H2_LEDGER_ARM_MISSING', { h2Arm });
      continue;
    }
    if (!nonEmptyString(entry.sourceArm)) {
      pushFailure(sourceFailures, 'H2_LEDGER_SOURCE_ARM_MISSING', { h2Arm });
      continue;
    }
    const raw = ledgerEntryToRawArm({
      ledgerText: String(entry.ledgerText ?? ''),
      sourceArm: entry.sourceArm,
      sourceLabel: nonEmptyString(entry.sourceLabel) ? entry.sourceLabel : null,
      scoreScale,
    });
    sourceLedgers[h2Arm] = raw.source;
    sourceFailures.push(...raw.failures.map((failure) => bridgeFailure(failure.code, { h2Arm, ...failure.detail })));
    if (raw.ok === true) rawArms[h2Arm] = raw.seedSeries;
  }

  const minSeeds = asNumber(config.minSeeds, 5);
  const minIterations = asNumber(config.minIterations, 8);
  for (const h2Arm of H2_LEDGER_REQUIRED_ARMS) {
    const source = sourceLedgers[h2Arm];
    if (!source) continue;
    if (asNumber(source.seedCount, 0) < minSeeds) {
      pushFailure(sourceFailures, 'H2_LEDGER_SEEDS_TOO_LOW', { h2Arm, sourceArm: source.sourceArm, seedCount: source.seedCount, minSeeds });
    }
    if (asNumber(source.minIterations, 0) < minIterations) {
      pushFailure(sourceFailures, 'H2_LEDGER_ITERATIONS_TOO_LOW', {
        h2Arm,
        sourceArm: source.sourceArm,
        minIterationsObserved: source.minIterations,
        minIterations,
      });
    }
  }

  const receipt = clone(baseReceiptProvided ? input.baseReceipt : buildH2Fixture('pass'));
  receipt.config = config;
  receipt.selfReportedVerdict = receipt.selfReportedVerdict ?? 'UNJUDGED';
  receipt.experiment = {
    schemaVersion: 1,
    derivedBy: H2_LEDGER_BRIDGE_VERSION,
    bridgeId: input.bridgeId ?? H2_LEDGER_BRIDGE_VERSION,
    scoreScale,
    requiredArms: [...H2_LEDGER_REQUIRED_ARMS],
    rawArms,
  };
  receipt.ledgerBridge = {
    schemaVersion: 1,
    bridgeVersion: H2_LEDGER_BRIDGE_VERSION,
    bridgeId: input.bridgeId ?? H2_LEDGER_BRIDGE_VERSION,
    baseReceiptProvided,
    scoreScale,
    sourceFailures,
    sourceLedgers,
    sourceLedgerCount: Object.keys(sourceLedgers).length,
  };
  Object.assign(receipt, deriveH2Fields(rawArms));
  return finalizeH2ExperimentReceipt(receipt);
}

/** @param {Record<string, any>} result @param {{code: string, detail?: any}[]} failures */
function withBridgeFailures(result, failures) {
  const protocolFailures = Array.isArray(result.protocolFailures) ? [...result.protocolFailures] : [];
  for (const failure of failures) {
    if (!protocolFailures.some((entry) => entry?.code === failure.code)) protocolFailures.push(failure);
  }
  const verdict = failures.length > 0 ? 'VOID' : result.verdict;
  return {
    ...result,
    verdict,
    validForH2Claim: verdict === 'PASS' && result.validForH2Claim === true && failures.length === 0,
    protocolFailures,
    bridgeFailures: failures,
    h2RescoreVerdict: result.verdict,
  };
}

/** @param {Record<string, any>} receipt */
export function evaluateH2LedgerBridgeReceipt(receipt) {
  const rescore = rescoreH2ExperimentReceipt(receipt);
  const bridge = isRecord(receipt?.ledgerBridge) ? receipt.ledgerBridge : null;
  const sourceFailures = Array.isArray(bridge?.sourceFailures)
    ? bridge.sourceFailures.map((failure) => bridgeFailure(String(failure.code ?? 'H2_LEDGER_FAILURE'), isRecord(failure.detail) ? failure.detail : {}))
    : [bridgeFailure('H2_LEDGER_BRIDGE_METADATA_MISSING')];
  const hashFailures = rescore.experimentReceiptHash.valid === true
    ? []
    : [bridgeFailure('H2_LEDGER_RECEIPT_HASH_MISMATCH', rescore.experimentReceiptHash)];
  const result = withBridgeFailures(rescore.result, [...sourceFailures, ...hashFailures]);
  return {
    ok: true,
    gate: 'h2-ledger-bridge',
    result,
    rescore,
    experimentReceiptHash: {
      declared: receipt?.experimentReceiptSha256 ?? null,
      actual: computeH2ExperimentReceiptHash(receipt ?? {}),
      valid: rescore.experimentReceiptHash.valid === true,
    },
  };
}

/** @param {{armLedgers?: Record<string, any>, baseReceipt?: Record<string, any>, config?: Record<string, any>, scoreScale?: number, bridgeId?: string}} input */
export function runH2LedgerBridge(input = {}) {
  const receipt = buildH2LedgerBridgeReceipt(input);
  return { ok: true, gate: 'h2-ledger-bridge', receipt, evaluation: evaluateH2LedgerBridgeReceipt(receipt) };
}

async function main() {
  const jsonMode = process.argv.includes('--json');
  const stdin = fs.readFileSync(0, 'utf8').trim();
  if (stdin.length === 0) {
    const help = { ok: true, gate: 'h2-ledger-bridge', mode: 'stdin-json', requiredArms: H2_LEDGER_REQUIRED_ARMS };
    process.stdout.write(`${JSON.stringify(help, null, 2)}\n`);
    return;
  }
  const payload = runH2LedgerBridge(JSON.parse(stdin));
  process.stdout.write(jsonMode ? `${JSON.stringify(payload, null, 2)}\n` : `${payload.evaluation.result.verdict}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`${error && error.stack ? error.stack : error}\n`);
    process.exit(1);
  });
}
