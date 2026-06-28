import * as childProcess from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { resolveAllowedRootForAbsolutePath } from './guard.js';
import { verifyFeedChain } from './emergence-feed.js';
import { ok, fail } from './server-helpers-result.js';

const MODE_VALUES = ['report', 'once'] as const;


function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function atomicSourceRoot(): string {
  const here = path.dirname(fileURLToPath(import.meta.url));
  return path.basename(here) === 'dist' ? path.resolve(here, '..') : here;
}

function defaultRepoRoot(): string {
  return path.resolve(atomicSourceRoot(), '..', '..');
}

function resolveCycleRoot(rawRoot: string | undefined): string {
  const candidate = rawRoot && rawRoot.trim().length > 0 ? path.resolve(rawRoot) : defaultRepoRoot();
  const allowedRoot = resolveAllowedRootForAbsolutePath(candidate);
  if (!allowedRoot) throw new Error(`repoRoot is outside the Atomic allowed roots: ${candidate}`);
  return candidate;
}

function readJsonl(absFile: string): Record<string, unknown>[] {
  if (!fs.existsSync(absFile)) return [];
  return fs.readFileSync(absFile, 'utf8')
    .split('\n')
    .filter((line) => line.trim().length > 0)
    .map((line) => {
      try {
        const parsed: unknown = JSON.parse(line);
        return isRecord(parsed) ? parsed : null;
      } catch {
        return null;
      }
    })
    .filter((entry): entry is Record<string, unknown> => entry !== null);
}

function sha256(value: string): string {
  return createHash('sha256').update(value).digest('hex');
}

function compact(value: string, maxBytes = 4000): string {
  return value.length > maxBytes ? `${value.slice(0, maxBytes)}...[truncated]` : value;
}

function parseJsonObject(stdout: string, label: string): Record<string, unknown> {
  try {
    const parsed: unknown = JSON.parse(stdout.trim() || '{}');
    if (!isRecord(parsed)) throw new Error('not an object');
    return parsed;
  } catch (error) {
    throw new Error(`${label} returned invalid JSON: ${error instanceof Error ? error.message : String(error)}; stdout=${compact(stdout, 1200)}`);
  }
}

function runSourceScript(scriptName: string, args: string[], repoRoot: string, timeoutMs: number): {
  status: number | null;
  signal: NodeJS.Signals | null;
  stdout: string;
  stderr: string;
} {
  const script = path.join(atomicSourceRoot(), scriptName);
  if (!fs.existsSync(script)) throw new Error(`emergence cycle script not found: ${script}`);
  const child = childProcess.spawnSync(process.execPath, [script, ...args], {
    cwd: atomicSourceRoot(),
    env: {
      ...process.env,
      ATOMIC_EDIT_REPO_ROOT: repoRoot,
      ATOMIC_SINGLE_TOOL_CALL: '',
      ATOMIC_SINGLE_TOOL_NAME: '',
      ATOMIC_SINGLE_TOOL_ARGS_JSON: '',
    },
    encoding: 'utf8',
    timeout: timeoutMs,
    maxBuffer: 48 * 1024 * 1024,
  });
  return {
    status: child.status,
    signal: child.signal,
    stdout: child.stdout ?? '',
    stderr: child.stderr ?? (child.error instanceof Error ? child.error.message : ''),
  };
}

function summarizeRoot(repoRoot: string): Record<string, unknown> {
  const atomicDir = path.join(repoRoot, '.atomic');
  const feed = readJsonl(path.join(atomicDir, 'emergence-feed.jsonl'));
  const corpus = readJsonl(path.join(atomicDir, 'disproof-corpus.jsonl'));
  const proposals = readJsonl(path.join(atomicDir, 'hypothesis-ledger.jsonl'));
  const lessons = readJsonl(path.join(atomicDir, 'lesson-rules.jsonl'));
  const lessonLedger = readJsonl(path.join(atomicDir, 'lesson-ledger.jsonl'));
  const semanticMemory = readJsonl(path.join(atomicDir, 'semantic-memory-ledger.jsonl'));
  const selfArchive = readJsonl(path.join(atomicSourceRoot(), 'self-evolution-archive.jsonl'));
  const feedChain = verifyFeedChain(feed as never[]);
  const lastCycle = [...feed].reverse().find((entry) => entry.kind === 'cycle') ?? null;
  const lastCycleSteps = Array.isArray(lastCycle?.steps) ? lastCycle.steps.filter(isRecord) : [];
  return {
    repoRoot,
    counts: {
      feedEvents: feed.length,
      corpusRecords: corpus.length,
      proposalLedgerRecords: proposals.length,
      lessonRules: lessons.length,
      lessonLedger: lessonLedger.length,
      semanticMemory: semanticMemory.length,
      selfEvolutionArchive: selfArchive.length,
    },
    feedChain,
    lastCycle: lastCycle ? {
      recordSha: typeof lastCycle.recordSha === 'string' ? lastCycle.recordSha : null,
      durationMs: typeof lastCycle.durationMs === 'number' ? lastCycle.durationMs : null,
      stepNames: lastCycleSteps.map((step) => String(step.name ?? '')),
      stepStatuses: lastCycleSteps.map((step) => ({ name: String(step.name ?? ''), ok: step.ok === true })),
      autonomousDecision: lastCycleSteps.find((step) => step.name === 'autonomous-evolution')?.parsed ?? null,
    } : null,
  };
}

function informativeCandidates(hypothesis: Record<string, unknown>): Record<string, unknown>[] {
  return Array.isArray(hypothesis.candidates)
    ? hypothesis.candidates.filter((candidate): candidate is Record<string, unknown> => isRecord(candidate) && candidate.informative === true)
    : [];
}

function buildOrgans(summary: Record<string, unknown>, hypothesis: Record<string, unknown>, reportText: string): Record<string, unknown>[] {
  const counts = isRecord(summary.counts) ? summary.counts : {};
  const feedChain = isRecord(summary.feedChain) ? summary.feedChain : {};
  const informative = informativeCandidates(hypothesis);
  const corpusRecords = Number(counts.corpusRecords ?? 0);
  const proposalRecords = Number(counts.proposalLedgerRecords ?? 0);
  const lessonRules = Number(counts.lessonRules ?? 0);
  const lessonLedger = Number(counts.lessonLedger ?? 0);
  const semanticMemory = Number(counts.semanticMemory ?? 0);
  const selfArchive = Number(counts.selfEvolutionArchive ?? 0);
  const swarmServer = path.join(defaultRepoRoot(), 'vendor', 'mcp-siblings', 'atomic-swarm', 'server.mjs');
  const swarmServerPresent = fs.existsSync(swarmServer);
  const hasSwarmFetch = swarmServerPresent && fs.readFileSync(swarmServer, 'utf8').includes('swarm_fetch');
  return [
    {
      id: 'generator',
      status: informative.length > 0 ? 'candidate-ready' : corpusRecords > 0 ? 'searching' : 'starved',
      evidence: { informativeCandidates: informative.length, corpusSize: hypothesis.corpusSize ?? 0, hitCount: hypothesis.hitCount ?? 0 },
    },
    {
      id: 'membrane',
      status: feedChain.ok === true ? 'hash-chain-intact' : 'chain-broken',
      evidence: { feedChain },
    },
    {
      id: 'world',
      status: hasSwarmFetch ? 'primitive-fetch-present-not-autonomous-ingest' : 'absent',
      evidence: { swarmFetchRegistered: hasSwarmFetch },
    },
    {
      id: 'library',
      status: lessonRules > 0 || lessonLedger > 0 ? 'learning-corpus-present' : corpusRecords > 0 ? 'negative-knowledge-only' : 'empty',
      evidence: { lessonRules, lessonLedger, corpusRecords },
    },
    {
      id: 'tower',
      status: selfArchive > 0 ? 'self-evolution-archive-present' : 'no-promotion-archive',
      evidence: { selfEvolutionArchive: selfArchive },
    },
    {
      id: 'swarm',
      status: swarmServerPresent ? 'surface-present' : 'absent',
      evidence: { swarmServerPresent },
    },
    {
      id: 'impulse',
      status: proposalRecords > 0 ? 'proposal-pressure-measured' : 'no-proposal-pressure-ledger',
      evidence: { proposalLedgerRecords: proposalRecords, informativeCandidates: informative.length },
    },
    {
      id: 'mirror',
      status: /no strong-emergence candidate/i.test(reportText) ? 'honest-refusal' : 'human-verification-required',
      evidence: { reportSha256: sha256(reportText), semanticMemory },
    },
  ];
}

function buildDecision(mode: (typeof MODE_VALUES)[number], summary: Record<string, unknown>, hypothesis: Record<string, unknown>, reportText: string): Record<string, unknown> {
  const informative = informativeCandidates(hypothesis);
  const lastCycle = isRecord(summary.lastCycle) ? summary.lastCycle : null;
  const autonomousDecision = isRecord(lastCycle?.autonomousDecision) ? lastCycle.autonomousDecision : null;
  const strongClaimAllowed = !/no strong-emergence candidate/i.test(reportText) && /candidate signal\(s\).*HUMAN VERIFICATION/i.test(reportText);
  const nextActions: Record<string, unknown>[] = [];
  if (autonomousDecision && typeof autonomousDecision.synthesized === 'string') {
    nextActions.push({
      action: 'review_then_promote_synthesized_gate_via_atomic_expand_self',
      gate: autonomousDecision.synthesized,
      fileRel: autonomousDecision.fileRel ?? null,
      coupling: autonomousDecision.coupling ?? null,
    });
  } else if (informative.length > 0) {
    nextActions.push({
      action: mode === 'once' ? 'inspect_autonomous_evolution_null_decision' : 'run_atomic_emergence_cycle_once_to_attempt_synthesis',
      topCoupling: {
        antecedent: informative[0].antecedent ?? null,
        consequent: informative[0].consequent ?? null,
        lift: informative[0].lift ?? null,
        holdoutConfidence: informative[0].holdoutConfidence ?? null,
      },
    });
  } else {
    nextActions.push({ action: 'harvest_more_verified_disproofs_before_gate_synthesis' });
  }
  if (!strongClaimAllowed) {
    nextActions.push({ action: 'refuse_10_10_claim_until_producer_independent_novel_family_resolve_is_measured' });
  }
  return {
    verdict: strongClaimAllowed ? 'candidate-signals-require-human-verification' : 'mechanical-weak-emergence-only',
    strongClaimAllowed,
    revolutionaryCompleteness: strongClaimAllowed ? 'candidate-not-proven' : 'not-yet-10/10',
    nextActions,
    proofLimits: [
      'atomic_emergence_cycle wires existing organs into an MCP/CLI pulse; it does not itself admit code or gates.',
      'A synthesized gate remains only a candidate until atomic_expand_self admits it through the full validator lattice.',
      'No AGI/cognition claim is allowed without a producer-independent, recomputable novel-family witness.',
    ],
  };
}

export function registerToolsEmergenceCycle(server: McpServer): void {
  server.registerTool(
    'atomic_emergence_cycle',
    {
      title: 'Atomic emergence cycle - live neuro-symbolic pulse',
      description:
        'Runs or reports the connected emergence loop over the current Atomic substrate: disproof corpus, hypothesis generator, ' +
        'autonomous-evolution decision surface, emergence feed, and honest mirror. Mode report is read-only; mode once runs the existing ' +
        'continuous-emergence-loop once and then verifies the resulting receipts. It never promotes code; promotion remains atomic_expand_self.',
      inputSchema: {
        mode: z.enum(MODE_VALUES).optional().describe('report = read-only pulse; once = run continuous-emergence-loop --once. Defaults to report.'),
        repoRoot: z.string().optional().describe('Optional repo root under the Atomic allowed roots. Defaults to the workspace repo root.'),
        timeoutMs: z.number().int().min(15000).max(300000).optional().describe('Per-script timeout. Defaults to 180000 for once, 60000 for report.'),
      },
    },
    async (a) => {
      try {
        const mode = (a.mode ?? 'report') as (typeof MODE_VALUES)[number];
        const repoRoot = resolveCycleRoot(a.repoRoot);
        const timeoutMs = typeof a.timeoutMs === 'number' ? a.timeoutMs : mode === 'once' ? 180000 : 60000;
        if (mode === 'once') {
          const loop = runSourceScript('continuous-emergence-loop.mjs', ['--once'], repoRoot, timeoutMs);
          if (loop.status !== 0) {
            return fail(`continuous emergence loop failed: status=${loop.status ?? loop.signal ?? 'unknown'} stderr=${compact(loop.stderr, 2000)} stdout=${compact(loop.stdout, 2000)}`);
          }
        }
        const hypothesisRun = runSourceScript('hypothesis-generator.mjs', [], repoRoot, timeoutMs);
        if (hypothesisRun.status !== 0) {
          return fail(`hypothesis generator failed: status=${hypothesisRun.status ?? hypothesisRun.signal ?? 'unknown'} stderr=${compact(hypothesisRun.stderr, 2000)}`);
        }
        const hypothesis = parseJsonObject(hypothesisRun.stdout, 'hypothesis-generator');
        const reportRun = runSourceScript('emergence-report.mjs', [repoRoot], repoRoot, timeoutMs);
        if (reportRun.status !== 0) {
          return fail(`emergence report failed: status=${reportRun.status ?? reportRun.signal ?? 'unknown'} stderr=${compact(reportRun.stderr, 2000)}`);
        }
        const summary = summarizeRoot(repoRoot);
        const reportText = reportRun.stdout.trim();
        const organs = buildOrgans(summary, hypothesis, reportText);
        const decision = buildDecision(mode, summary, hypothesis, reportText);
        return ok({
          ok: true,
          changed: mode === 'once',
          mode,
          repoRoot,
          summary,
          organs,
          hypothesis: {
            corpusSize: hypothesis.corpusSize ?? 0,
            hitCount: hypothesis.hitCount ?? 0,
            summary: hypothesis.summary ?? {},
            informativeCandidates: informativeCandidates(hypothesis).slice(0, 8),
          },
          emergenceReport: {
            text: reportText,
            sha256: sha256(reportText),
          },
          decision,
          receiptSha256: sha256(JSON.stringify({ mode, repoRoot, summary, organs, hypothesis, reportText, decision })),
        });
      } catch (error) {
        return fail(error instanceof Error ? error.message : String(error));
      }
    },
  );
}
