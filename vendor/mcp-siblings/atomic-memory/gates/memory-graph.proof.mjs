#!/usr/bin/env node
import { spawn } from 'node:child_process';
import path from 'node:path';
import fs from 'node:fs';
import crypto from 'node:crypto';
import assert from 'node:assert';
import { fileURLToPath } from 'node:url';

const jsonMode = process.argv.includes('--json');
const here = path.dirname(fileURLToPath(import.meta.url));
const serverPath = path.join(here, '..', 'server.mjs');
const repoRoot = path.join(here, '.memory-graph-proof-' + process.pid);
const atomicDir = path.join(repoRoot, '.atomic');
const coreAtomicDir = path.join(repoRoot, 'core', 'atomic-edit', '.atomic');
const sha256 = (s) => crypto.createHash('sha256').update(s).digest('hex');
const results = [];
function record(name, ok, detail = {}) { results.push({ name, ok: Boolean(ok), detail }); }
function bodyHash(body) { return sha256(JSON.stringify(body)); }
function writeJsonl(file, records) { fs.writeFileSync(file, records.map((record) => JSON.stringify(record)).join('\n') + '\n'); }

fs.rmSync(repoRoot, { recursive: true, force: true });
fs.mkdirSync(atomicDir, { recursive: true });
fs.mkdirSync(coreAtomicDir, { recursive: true });

const proc = spawn(process.execPath, ['--experimental-sqlite', serverPath], {
  cwd: repoRoot,
  env: { ...process.env, ATOMIC_REPO_ROOT: repoRoot, ATOMIC_SWARM_REPO_ROOT: repoRoot },
  stdio: ['pipe', 'pipe', 'pipe'],
});
let buffer = '';
let messageId = 1;
const pending = new Map();
proc.stdout.on('data', (data) => {
  buffer += data.toString();
  let newlineIndex;
  while ((newlineIndex = buffer.indexOf('\n')) !== -1) {
    const line = buffer.slice(0, newlineIndex).trim();
    buffer = buffer.slice(newlineIndex + 1);
    if (!line) continue;
    try {
      const response = JSON.parse(line);
      if (response.id && pending.has(response.id)) {
        const { resolve, reject } = pending.get(response.id);
        pending.delete(response.id);
        response.error ? reject(new Error(JSON.stringify(response.error))) : resolve(response);
      }
    } catch {}
  }
});
proc.stderr.on('data', () => {});
function cleanup() {
  try { proc.stdin.end(); } catch {}
  try { if (proc.exitCode === null && proc.signalCode === null) proc.kill(); } catch {}
  fs.rmSync(repoRoot, { recursive: true, force: true });
}
function sendRequest(method, params) {
  return new Promise((resolve, reject) => {
    const id = messageId++;
    pending.set(id, { resolve, reject });
    proc.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
  });
}
function parseTool(response) { return JSON.parse(response.result.content[0].text); }

try {
  await new Promise((resolve) => setTimeout(resolve, 500));
  const memoryResponse = await sendRequest('tools/call', {
    name: 'memory_record',
    arguments: {
      intent: 'Graph proof records OAuth2 memory for src/auth.ts and the authenticateUser symbol.',
      relatedFiles: ['src/auth.ts'],
      relatedTaskIds: [7],
      tags: ['graph', 'oauth2'],
      symbols: ['authenticateUser'],
      lockIds: ['lock-auth-graph'],
      gitCommit: 'abc123',
    },
  });
  const memory = parseTool(memoryResponse);
  assert(memory.ok === true, 'memory_record failed');

  fs.writeFileSync(path.join(atomicDir, 'swarm-tasks.json'), JSON.stringify({ nextId: 8, tasks: [{ id: 7, subject: 'graph task', status: 'in_progress', claimedBy: 'worker-a', completion: null }] }, null, 2));
  writeJsonl(path.join(atomicDir, 'swarm-tasks-ledger.jsonl'), [{ at: '2026-06-28T00:00:00.000Z', tool: 'swarm_task_create', id: 7, subject: 'graph task' }]);

  const lessonBody = {
    kind: 'atomic-effect-lesson-record',
    schemaVersion: 1,
    sequence: 1,
    previousRecordSha256: null,
    lessonId: 'lesson:graph-proof',
    effect: { gatesFlipped: ['graph:RED->GREEN'] },
    operator: { file: 'src/auth.ts', op: 'replace_text', oldText: 'a', newText: 'b' },
    decision: 'accept',
    context: { intent: 'Graph proof lesson', ts: 1782620001000 },
  };
  writeJsonl(path.join(coreAtomicDir, 'lesson-ledger.jsonl'), [{ ...lessonBody, recordSha256: bodyHash(lessonBody) }]);

  const eventBody = {
    v: 1,
    kind: 'edit',
    ts: 1782620000000,
    agent: 'proof',
    op: 'atomicWrite',
    file: 'src/auth.ts',
    semanticMemoryRecall: { status: 'hit', query: { file: 'src/auth.ts', beforeSha256: sha256('a'), afterSha256: sha256('b'), tokens: ['src/auth.ts'] }, sources: ['semantic-memory-ledger'], matches: [{ source: 'semantic-memory-ledger', id: memory.hash }], digest: sha256('recall') },
  };
  const secondEventBody = {
    v: 1,
    kind: 'edit',
    ts: 1782620000500,
    agent: 'proof',
    op: 'atomicWrite',
    file: 'src/auth.ts',
  };
  const firstEventRecord = { ...eventBody, previousSha: null, recordSha: sha256(JSON.stringify({ event: eventBody, previousSha: null })) };
  const secondEventRecord = { ...secondEventBody, previousSha: firstEventRecord.recordSha, recordSha: sha256(JSON.stringify({ event: secondEventBody, previousSha: firstEventRecord.recordSha })) };
  writeJsonl(path.join(atomicDir, 'emergence-feed.jsonl'), [firstEventRecord, secondEventRecord]);

  const graphResponse = await sendRequest('tools/call', { name: 'memory_graph', arguments: { limit: 100 } });
  const graph = parseTool(graphResponse);
  record('memory_graph returns a receipt-hashed graph', graph.ok === true && /^[0-9a-f]{64}$/.test(graph.graphSha256), { graphSha256: graph.graphSha256 });
  record('graph includes verified semantic memory, task, lesson, event, file, symbol, and agent nodes',
    ['memory', 'task', 'lesson', 'emergence_event', 'file', 'symbol', 'agent'].every((type) => graph.nodes.some((node) => node.type === type)),
    { nodeTypes: [...new Set(graph.nodes.map((node) => node.type))] });
  record('graph connects memory/files/tasks/symbols and emergence recall edges',
    ['mentions_file', 'mentions_task', 'mentions_symbol', 'observed_file', 'recalled'].every((type) => graph.edges.some((edge) => edge.type === type)),
    { edgeTypes: [...new Set(graph.edges.map((edge) => edge.type))] });
  record('graph derives honest temporal causal candidates from verified emergence and lesson records',
    ['precedes_on_file', 'causal_candidate'].every((type) => graph.edges.some((edge) => edge.type === type)) && graph.sources.causalEdges >= 2,
    { edgeTypes: [...new Set(graph.edges.map((edge) => edge.type))], causalEdges: graph.sources.causalEdges });
  const causalQueryResponse = await sendRequest('tools/call', { name: 'memory_graph', arguments: { query: 'causal_candidate', limit: 2 } });
  const causalQuery = parseTool(causalQueryResponse);
  record('graph query can select relationship types and return their endpoints',
    causalQuery.edges.some((edge) => edge.type === 'causal_candidate') && causalQuery.nodes.length >= 2,
    { edgeTypes: [...new Set(causalQuery.edges.map((edge) => edge.type))], nodeCount: causalQuery.nodes.length });
  record('graph reports bounded source counts from all local ledgers',
    graph.sources.atomicDirs === 2 && graph.sources.semanticMemory >= 1 && graph.sources.swarmTasks === 1 && graph.sources.lessons === 1 && graph.sources.emergence === 2,
    graph.sources);
} catch (error) {
  record('memory_graph proof execution', false, { error: error instanceof Error ? error.message : String(error) });
} finally {
  cleanup();
}

const failed = results.filter((result) => !result.ok);
const payload = { ok: failed.length === 0, total: results.length, failed, results };
if (jsonMode) console.log(JSON.stringify(payload, null, 2));
else for (const result of results) console.log((result.ok ? 'PASS ' : 'FAIL ') + result.name);
process.exit(payload.ok ? 0 : 1);
