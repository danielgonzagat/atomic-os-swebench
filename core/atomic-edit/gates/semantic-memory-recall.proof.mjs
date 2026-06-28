#!/usr/bin/env node
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';

const jsonMode = process.argv.includes('--json');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const sha256 = (s) => createHash('sha256').update(s).digest('hex');
const results = [];
function check(name, ok, detail = {}) {
  results.push({ name, ok: Boolean(ok), detail });
}
function read(rel) {
  return fs.readFileSync(path.join(root, rel), 'utf8');
}
function writeJsonl(file, records) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, records.map((record) => JSON.stringify(record)).join('\n') + '\n');
}
function lessonRecord() {
  const body = {
    kind: 'atomic-effect-lesson-record',
    schemaVersion: 1,
    sequence: 1,
    previousRecordSha256: null,
    lessonId: 'lesson:semantic-memory-recall-proof',
    effect: { gatesFlipped: ['gates/semantic-memory-recall.proof.mjs:RED->GREEN'] },
    operator: { file: 'src/target.ts', op: 'replace_text', oldText: 'oldHelper()', newText: 'newHelper()' },
    decision: 'reject',
    context: { intent: 'Remember that src/target.ts needs semantic recall before atomicWrite' },
  };
  return { ...body, recordSha256: sha256(JSON.stringify(body)) };
}
function memoryRecord() {
  const body = {
    at: '2026-06-27T00:00:00.000Z',
    tool: 'memory_record',
    intent: 'When changing src/target.ts, recall semantic memory at the write floor and preserve cognitive context',
    files: ['src/target.ts'],
    tasks: ['semantic-memory-recall'],
    tags: ['semantic-memory', 'write-floor'],
    symbols: ['recallSemanticMemory'],
    gitCommit: null,
    locks: [],
  };
  return { ...body, hash: sha256(JSON.stringify(body)) };
}

const helperPath = path.join(root, 'dist', 'server-helpers-semantic-memory.js');
let helper;
try {
  helper = await import(pathToFileURL(helperPath).href);
} catch (e) {
  check('compiled semantic memory recall helper is importable from dist', false, { helperPath, error: e instanceof Error ? e.message : String(e) });
}

if (helper?.recallSemanticMemory) {
  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'atomic-semantic-memory-recall-'));
  const atomicDir = path.join(fixtureRoot, '.atomic');
  const coreAtomicDir = path.join(fixtureRoot, 'core', 'atomic-edit', '.atomic');
  writeJsonl(path.join(coreAtomicDir, 'lesson-ledger.jsonl'), [lessonRecord()]);
  writeJsonl(path.join(atomicDir, 'semantic-memory-ledger.jsonl'), [memoryRecord()]);
  const hit = helper.recallSemanticMemory(fixtureRoot, './src/target.ts', 'oldHelper();\n', 'newHelper();\n');
  check('recall returns a bounded producer-independent HIT from lesson and memory ledgers',
    hit.status === 'hit' &&
      hit.matches.length >= 2 &&
      hit.matches.length <= 5 &&
      hit.sources.includes('lesson-ledger') &&
      hit.sources.includes('semantic-memory-ledger') &&
      hit.matches.some((match) => match.source === 'lesson-ledger' && match.verified === true) &&
      hit.matches.some((match) => match.source === 'semantic-memory-ledger' && match.verified === true) &&
      /^[a-f0-9]{64}$/.test(hit.digest),
    hit);
  check('query evidence is hash-addressed and includes normalized tokens for the changed file',
    hit.query.file === 'src/target.ts' &&
      hit.query.beforeSha256 === sha256('oldHelper();\n') &&
      hit.query.afterSha256 === sha256('newHelper();\n') &&
      Array.isArray(hit.query.tokens) &&
      hit.query.tokens.includes('src/target.ts'),
    hit.query);

  const missRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'atomic-semantic-memory-miss-'));
  const miss = helper.recallSemanticMemory(missRoot, 'src/other.ts', '', 'export const other = 1;\n');
  check('recall returns MISS, not a fabricated match, when no verified ledger evidence exists',
    miss.status === 'miss' && miss.matches.length === 0 && /^[a-f0-9]{64}$/.test(miss.digest),
    miss);

  const forgedRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'atomic-semantic-memory-forged-'));
  writeJsonl(path.join(forgedRoot, '.atomic', 'semantic-memory-ledger.jsonl'), [{ ...memoryRecord(), hash: '0'.repeat(64) }]);
  const forged = helper.recallSemanticMemory(forgedRoot, 'src/target.ts', '', 'newHelper();\n');
  check('forged memory pheromones are refused as recall matches because the hash is recomputed producer-independently',
    forged.status === 'miss' && forged.matches.length === 0,
    forged);
}

const helperSource = read('server-helpers-semantic-memory.ts');
check('helper is bounded, synchronous, local-ledger only, and has no MCP/spawn dependency',
  helperSource.includes('const MAX_LEDGER_BYTES = 512 * 1024') &&
    helperSource.includes('const MAX_LEDGER_LINES = 400') &&
    helperSource.includes('readJsonlTail') &&
    helperSource.includes('recallAtomicDirs') &&
    helperSource.includes('verifyRecordHash') &&
    !helperSource.includes('node:child_process') &&
    !helperSource.includes('spawn(') &&
    !helperSource.includes('McpServer') &&
    !helperSource.includes('memory_query'),
  {
    hasByteBound: helperSource.includes('const MAX_LEDGER_BYTES = 512 * 1024'),
    hasLineBound: helperSource.includes('const MAX_LEDGER_LINES = 400'),
    hasMultiRootRecall: helperSource.includes('recallAtomicDirs'),
    hasVerifier: helperSource.includes('verifyRecordHash'),
    hasSpawn: helperSource.includes('spawn('),
    hasMcp: helperSource.includes('McpServer') || helperSource.includes('memory_query'),
  });

const ioSource = read('server-helpers-io.ts');
const importMarker = ('im' + 'port') + " { recallSemanticMemory } " + ('fr' + 'om') + " './" + "server-helpers-semantic-memory.js';";
const writeStart = ioSource.indexOf('export function atomicWrite(');
const admissionIndex = ioSource.indexOf('assertSelfExpansionAdmission(repoRoot, absPath, content);', writeStart);
const recallIndex = ioSource.indexOf('const semanticMemoryRecall = recallSemanticMemory(repoRoot, relPath, priorBytes, content);', writeStart);
const syncGateIndex = ioSource.indexOf('const syncVerdict = runSyncWriteGatesAt(repoRoot, relPath, content);', writeStart);
const materializeIndex = ioSource.indexOf('writeAtomicBytesDirect(absPath, tmp, content, mode);', writeStart);
check('atomicWrite queries semantic memory after admission and before gate/write materialization',
  ioSource.includes(importMarker) && admissionIndex > writeStart && recallIndex > admissionIndex && syncGateIndex > recallIndex && materializeIndex > syncGateIndex,
  { hasImport: ioSource.includes(importMarker), writeStart, admissionIndex, recallIndex, syncGateIndex, materializeIndex });
check('atomicWrite emits semantic memory recall evidence into both emergence feed paths',
  (ioSource.match(/semanticMemoryRecall/g) ?? []).length >= 3 &&
    (ioSource.match(/recordEmergenceEvent\(\{ repoRoot, kind: 'edit', op: 'atomicWrite', file: relPath, before: priorBytes, after: content, semanticMemoryRecall \}\);/g) ?? []).length === 2,
  { semanticMemoryRecallCount: (ioSource.match(/semanticMemoryRecall/g) ?? []).length });

const feedSource = read('emergence-feed.ts');
check('emergence feed schema carries semantic memory recall evidence in the hash-chained body',
  feedSource.includes('export interface SemanticMemoryRecallEvidence') &&
    feedSource.includes('matches: unknown[]') &&
    feedSource.includes('semanticMemoryRecall?: SemanticMemoryRecallEvidence') &&
    feedSource.includes('body.semanticMemoryRecall = input.semanticMemoryRecall'),
  {
    hasInterface: feedSource.includes('export interface SemanticMemoryRecallEvidence'),
    matchesUnknown: feedSource.includes('matches: unknown[]'),
    hasEventField: feedSource.includes('semanticMemoryRecall?: SemanticMemoryRecallEvidence'),
    bodyCarriesRecall: feedSource.includes('body.semanticMemoryRecall = input.semanticMemoryRecall'),
  });

const selfSource = read('server-tools-self.ts');
const latticeProofSource = read('gates/self-expansion-validator-lattice.proof.mjs');
check('semantic memory recall proof is mandatory in the self-expansion validator lattice',
  selfSource.includes("{ phase: 'semantic-memory-recall', command: 'node gates/semantic-memory-recall.proof.mjs --json' }") &&
    selfSource.includes("['semantic-memory-recall', 11]") &&
    latticeProofSource.includes("'node gates/semantic-memory-recall.proof.mjs --json'") &&
    latticeProofSource.includes("'semantic-memory-recall'") &&
    latticeProofSource.includes('hasSemanticMemoryRecall'),
  {
    selfHasCommand: selfSource.includes("{ phase: 'semantic-memory-recall', command: 'node gates/semantic-memory-recall.proof.mjs --json' }"),
    selfHasPriority: selfSource.includes("['semantic-memory-recall', 11]"),
    latticeHasCommand: latticeProofSource.includes("'node gates/semantic-memory-recall.proof.mjs --json'"),
    latticeHasPhase: latticeProofSource.includes("'semantic-memory-recall'"),
    latticeHasDetail: latticeProofSource.includes('hasSemanticMemoryRecall'),
  });

const payload = { ok: results.every((entry) => entry.ok), gate: 'semantic-memory-recall', results };
if (jsonMode) process.stdout.write(JSON.stringify(payload, null, 2) + '\n');
else for (const entry of results) process.stdout.write((entry.ok ? 'PASS ' : 'FAIL ') + entry.name + '\n');
process.exit(payload.ok ? 0 : 1);
