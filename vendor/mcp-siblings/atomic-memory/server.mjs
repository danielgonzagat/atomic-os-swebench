#!/usr/bin/env node
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import os from 'node:os';
import { minimalRecomputableDisproof } from '../atomic-edit-evolution/minimal-core.mjs';
import { funnelGate, decompose } from '../atomic-edit-evolution/truth-funnel.mjs';
import { buildFrictionLedger, routeBatch } from '../atomic-edit-evolution/friction-router.mjs';
import { wavefrontOf } from '../atomic-edit-evolution/e1-fusion.mjs';

const server = new McpServer({ name: 'atomic-memory', version: '1.0.0' });
const REPO_ROOT = process.env.ATOMIC_REPO_ROOT || process.env.ATOMIC_SWARM_REPO_ROOT || process.cwd();
const ATOMIC_DIR = path.join(REPO_ROOT, '.atomic');
const LEDGER_FILE = path.join(ATOMIC_DIR, 'semantic-memory-ledger.jsonl');

if (!fs.existsSync(ATOMIC_DIR)) {
  fs.mkdirSync(ATOMIC_DIR, { recursive: true });
}

// ── SQLite initialization with fallback ─────────────────────────────
let db = null;
try {
  const { DatabaseSync } = await import('node:sqlite');
  const dbFile = path.join(ATOMIC_DIR, 'semantic-memory.db');
  db = new DatabaseSync(dbFile);

  db.exec(`
    CREATE TABLE IF NOT EXISTS memories (
      hash TEXT PRIMARY KEY,
      at TEXT NOT NULL,
      tool TEXT NOT NULL,
      intent TEXT NOT NULL,
      git_commit TEXT
    );
    CREATE TABLE IF NOT EXISTS memory_files (
      memory_hash TEXT,
      file_path TEXT,
      PRIMARY KEY (memory_hash, file_path),
      FOREIGN KEY (memory_hash) REFERENCES memories(hash) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS memory_tasks (
      memory_hash TEXT,
      task_id TEXT,
      PRIMARY KEY (memory_hash, task_id),
      FOREIGN KEY (memory_hash) REFERENCES memories(hash) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS memory_tags (
      memory_hash TEXT,
      tag TEXT,
      PRIMARY KEY (memory_hash, tag),
      FOREIGN KEY (memory_hash) REFERENCES memories(hash) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS memory_symbols (
      memory_hash TEXT,
      symbol TEXT,
      PRIMARY KEY (memory_hash, symbol),
      FOREIGN KEY (memory_hash) REFERENCES memories(hash) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS memory_locks (
      memory_hash TEXT,
      lock_id TEXT,
      PRIMARY KEY (memory_hash, lock_id),
      FOREIGN KEY (memory_hash) REFERENCES memories(hash) ON DELETE CASCADE
    );
  `);
} catch (e) {
  console.warn('[atomic-memory] SQLite database not available, falling back to JSONL-only indexing:', e.message);
}

function insertMemoryToDb(entry) {
  if (!db) return;
  try {
    const insertMem = db.prepare(`
      INSERT OR IGNORE INTO memories (hash, at, tool, intent, git_commit)
      VALUES (?, ?, ?, ?, ?)
    `);
    insertMem.run(
      entry.hash,
      entry.at,
      entry.tool,
      entry.intent,
      entry.gitCommit || null
    );

    if (entry.files) {
      const insertFile = db.prepare(`INSERT OR IGNORE INTO memory_files (memory_hash, file_path) VALUES (?, ?)`);
      for (const f of entry.files) insertFile.run(entry.hash, f);
    }
    if (entry.tasks) {
      const insertTask = db.prepare(`INSERT OR IGNORE INTO memory_tasks (memory_hash, task_id) VALUES (?, ?)`);
      for (const t of entry.tasks) insertTask.run(entry.hash, String(t));
    }
    if (entry.tags) {
      const insertTag = db.prepare(`INSERT OR IGNORE INTO memory_tags (memory_hash, tag) VALUES (?, ?)`);
      for (const t of entry.tags) insertTag.run(entry.hash, t);
    }
    if (entry.symbols) {
      const insertSymbol = db.prepare(`INSERT OR IGNORE INTO memory_symbols (memory_hash, symbol) VALUES (?, ?)`);
      for (const s of entry.symbols) insertSymbol.run(entry.hash, s);
    }
    if (entry.locks) {
      const insertLock = db.prepare(`INSERT OR IGNORE INTO memory_locks (memory_hash, lock_id) VALUES (?, ?)`);
      for (const l of entry.locks) insertLock.run(entry.hash, l);
    }
  } catch (e) {
    console.error('[atomic-memory] Failed to insert memory to SQLite:', e);
  }
}

function syncDatabase() {
  if (!db) return;
  if (!fs.existsSync(LEDGER_FILE)) return;
  try {
    const lines = fs.readFileSync(LEDGER_FILE, 'utf-8').split('\n').filter(Boolean);
    db.exec('BEGIN TRANSACTION');
    for (const line of lines) {
      try {
        const entry = JSON.parse(line);
        if (entry.hash) {
          insertMemoryToDb(entry);
        }
      } catch {}
    }
    db.exec('COMMIT');
  } catch (e) {
    try { db.exec('ROLLBACK'); } catch {}
    console.error('[atomic-memory] Failed to sync SQLite database:', e);
  }
}

function querySQLite(args) {
  let queryStr = `
    SELECT DISTINCT m.hash, m.at, m.tool, m.intent, m.git_commit as gitCommit
    FROM memories m
  `;
  const joins = [];
  const wheres = [];
  const params = [];

  if (args.tag) {
    joins.push('JOIN memory_tags tg ON m.hash = tg.memory_hash');
    wheres.push('tg.tag = ?');
    params.push(args.tag);
  }
  if (args.file) {
    joins.push('JOIN memory_files f ON m.hash = f.memory_hash');
    wheres.push('f.file_path = ?');
    params.push(args.file);
  }
  if (args.taskId) {
    joins.push('JOIN memory_tasks tsk ON m.hash = tsk.memory_hash');
    wheres.push('tsk.task_id = ?');
    params.push(String(args.taskId));
  }
  if (args.symbol) {
    joins.push('JOIN memory_symbols sym ON m.hash = sym.memory_hash');
    wheres.push('sym.symbol = ?');
    params.push(args.symbol);
  }
  if (args.lockId) {
    joins.push('JOIN memory_locks lk ON m.hash = lk.memory_hash');
    wheres.push('lk.lock_id = ?');
    params.push(args.lockId);
  }
  if (args.query) {
    const terms = String(args.query).toLowerCase().split(/\s+/).filter(Boolean);
    for (const t of terms) {
      wheres.push('LOWER(m.intent) LIKE ?');
      params.push(`%${t}%`);
    }
  }

  if (joins.length > 0) queryStr += '\n' + joins.join('\n');
  if (wheres.length > 0) queryStr += '\nWHERE ' + wheres.join(' AND ');
  queryStr += '\nORDER BY m.at DESC';

  const stmt = db.prepare(queryStr);
  const rows = stmt.all(...params);

  const results = [];
  for (const row of rows) {
    const files = db.prepare('SELECT file_path FROM memory_files WHERE memory_hash = ?').all(row.hash).map(r => r.file_path);
    const tasks = db.prepare('SELECT task_id FROM memory_tasks WHERE memory_hash = ?').all(row.hash).map(r => r.task_id);
    const tags = db.prepare('SELECT tag FROM memory_tags WHERE memory_hash = ?').all(row.hash).map(r => r.tag);
    const symbols = db.prepare('SELECT symbol FROM memory_symbols WHERE memory_hash = ?').all(row.hash).map(r => r.symbol);
    const locks = db.prepare('SELECT lock_id FROM memory_locks WHERE memory_hash = ?').all(row.hash).map(r => r.lock_id);

    results.push({
      hash: row.hash,
      at: row.at,
      tool: row.tool,
      intent: row.intent,
      gitCommit: row.gitCommit,
      files,
      tasks,
      tags,
      symbols,
      locks
    });
  }
  return results;
}


const GRAPH_MAX_LEDGER_BYTES = 1024 * 1024;
const GRAPH_MAX_LEDGER_LINES = 1000;
const GRAPH_MAX_LIMIT = 1000;
const GRAPH_MAX_CAUSAL_EDGES = 200;
const GRAPH_CAUSAL_WINDOW_MS = 24 * 60 * 60 * 1000;

function stableJson(value) {
  if (value === undefined) return 'null';
  if (value === null || typeof value !== 'object') return JSON.stringify(value) ?? 'null';
  if (Array.isArray(value)) return '[' + value.map(stableJson).join(',') + ']';
  return '{' + Object.keys(value).sort().map((key) => JSON.stringify(key) + ':' + stableJson(value[key])).join(',') + '}';
}

function graphSha(value) {
  return crypto.createHash('sha256').update(stableJson(value)).digest('hex');
}

function readJsonlTail(file) {
  try {
    if (!fs.existsSync(file)) return [];
    const stat = fs.statSync(file);
    if (!stat.isFile() || stat.size <= 0) return [];
    const length = Math.min(stat.size, GRAPH_MAX_LEDGER_BYTES);
    const start = Math.max(0, stat.size - length);
    const buffer = Buffer.alloc(length);
    const fd = fs.openSync(file, 'r');
    try { fs.readSync(fd, buffer, 0, length, start); } finally { fs.closeSync(fd); }
    const lines = buffer.toString('utf8').split('\n');
    if (start > 0 && lines.length > 0) lines.shift();
    const records = [];
    for (const line of lines.filter(Boolean).slice(-GRAPH_MAX_LEDGER_LINES)) {
      try {
        const parsed = JSON.parse(line);
        if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) records.push(parsed);
      } catch {}
    }
    return records;
  } catch {
    return [];
  }
}

function readJsonFile(file, fallback) {
  try {
    const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
    return parsed ?? fallback;
  } catch {
    return fallback;
  }
}

function graphAtomicDirs() {
  const candidates = [
    ATOMIC_DIR,
    path.join(REPO_ROOT, 'core', 'atomic-edit', '.atomic'),
  ];
  const seen = new Set();
  const dirs = [];
  for (const candidate of candidates) {
    const resolved = path.resolve(candidate);
    if (seen.has(resolved) || !fs.existsSync(resolved)) continue;
    seen.add(resolved);
    dirs.push(resolved);
  }
  return dirs;
}

function readJsonlTailMany(fileName, atomicDirs) {
  const out = [];
  for (const dir of atomicDirs) out.push(...readJsonlTail(path.join(dir, fileName)));
  return out;
}

function verifyObjectHash(record, hashField) {
  const expected = typeof record?.[hashField] === 'string' ? record[hashField] : '';
  if (!/^[0-9a-f]{64}$/.test(expected)) return null;
  const body = {};
  for (const key of Object.keys(record)) {
    if (key !== hashField) body[key] = record[key];
  }
  return crypto.createHash('sha256').update(JSON.stringify(body)).digest('hex') === expected ? expected : null;
}

function verifyEmergenceRecord(record) {
  const expected = typeof record?.recordSha === 'string' ? record.recordSha : '';
  if (!/^[0-9a-f]{64}$/.test(expected)) return null;
  const { previousSha, recordSha, ...body } = record;
  const actual = crypto.createHash('sha256').update(JSON.stringify({ event: body, previousSha: previousSha ?? null })).digest('hex');
  return actual === expected ? expected : null;
}

function arrayOfStrings(value) {
  return Array.isArray(value) ? value.filter((item) => typeof item === 'string' && item.length > 0) : [];
}

function timestampMs(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim()) {
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function pushMapList(map, key, value) {
  if (!key) return;
  const list = map.get(key) || [];
  list.push(value);
  map.set(key, list);
}

function addTemporalCausalEdges(edges, fileEventFacts, lessonFacts) {
  let added = 0;
  // Richer lesson-linked candidates first: plain file precedence must not starve the actual causal hypothesis layer.
  for (const lesson of lessonFacts) {
    if (!Number.isFinite(lesson.ts)) continue;
    const candidates = (fileEventFacts.get(lesson.file) || [])
      .filter((fact) => Number.isFinite(fact.ts) && fact.ts <= lesson.ts && lesson.ts - fact.ts <= GRAPH_CAUSAL_WINDOW_MS)
      .sort((a, b) => b.ts - a.ts)
      .slice(0, 3);
    for (const fact of candidates) {
      if (added >= GRAPH_MAX_CAUSAL_EDGES) return added;
      addEdge(edges, fact.id, lesson.id, 'causal_candidate', {
        file: lesson.file,
        deltaMs: lesson.ts - fact.ts,
        basis: 'same-file-before-verified-lesson',
        decision: lesson.decision ?? null,
      });
      added += 1;
    }
  }
  for (const [file, facts] of fileEventFacts) {
    const ordered = facts.filter((fact) => Number.isFinite(fact.ts)).sort((a, b) => a.ts - b.ts);
    for (let i = 1; i < ordered.length && added < GRAPH_MAX_CAUSAL_EDGES; i += 1) {
      addEdge(edges, ordered[i - 1].id, ordered[i].id, 'precedes_on_file', {
        file,
        deltaMs: ordered[i].ts - ordered[i - 1].ts,
        basis: 'verified-emergence-ts',
      });
      added += 1;
    }
  }
  return added;
}

function addNode(nodes, node) {
  if (!node?.id) return;
  const existing = nodes.get(node.id) || {};
  nodes.set(node.id, { ...existing, ...node });
}

function addEdge(edges, from, to, type, data = {}) {
  if (!from || !to || !type) return;
  edges.push({ from, to, type, ...data });
}

function sourceText(value) {
  return stableJson(value).toLowerCase();
}

function graphFilter(nodes, edges, query) {
  const needle = typeof query === 'string' ? query.trim().toLowerCase() : '';
  if (!needle) return { nodes: [...nodes.values()], edges };
  const direct = new Set();
  for (const node of nodes.values()) {
    if (sourceText(node).includes(needle)) direct.add(node.id);
  }
  const keep = new Set(direct);
  const matchedEdges = new Set();
  for (const edge of edges) {
    if (sourceText(edge).includes(needle)) {
      matchedEdges.add(edge);
      keep.add(edge.from);
      keep.add(edge.to);
      continue;
    }
    if (direct.has(edge.from) || direct.has(edge.to)) {
      keep.add(edge.from);
      keep.add(edge.to);
    }
  }
  return {
    nodes: [...nodes.values()].filter((node) => keep.has(node.id)),
    edges: edges.filter((edge) => matchedEdges.has(edge) || (keep.has(edge.from) && keep.has(edge.to))),
  };
}

function buildMemoryGraph(args = {}) {
  const limit = Math.min(Math.max(Number(args.limit ?? 200) || 200, 1), GRAPH_MAX_LIMIT);
  const nodes = new Map();
  const edges = [];
  const sourceCounts = {};
  const fileEventFacts = new Map();
  const lessonFacts = [];
  const atomicDir = ATOMIC_DIR;
  const atomicDirs = graphAtomicDirs();
  sourceCounts.atomicDirs = atomicDirs.length;

  const memoryRecords = readJsonlTailMany('semantic-memory-ledger.jsonl', atomicDirs);
  sourceCounts.semanticMemory = memoryRecords.length;
  for (const record of memoryRecords) {
    const hash = verifyObjectHash(record, 'hash');
    if (!hash || record.tool !== 'memory_record') continue;
    const memoryId = 'memory:' + hash;
    addNode(nodes, { id: memoryId, type: 'memory', source: 'semantic-memory-ledger', verified: true, label: String(record.intent || '').slice(0, 160), at: record.at, gitCommit: record.gitCommit ?? null });
    for (const file of arrayOfStrings(record.files)) {
      const fileId = 'file:' + file;
      addNode(nodes, { id: fileId, type: 'file', label: file });
      addEdge(edges, memoryId, fileId, 'mentions_file');
    }
    for (const task of arrayOfStrings(record.tasks)) {
      const taskId = 'task:' + task;
      addNode(nodes, { id: taskId, type: 'task', label: task });
      addEdge(edges, memoryId, taskId, 'mentions_task');
    }
    for (const tag of arrayOfStrings(record.tags)) {
      const tagId = 'tag:' + tag;
      addNode(nodes, { id: tagId, type: 'tag', label: tag });
      addEdge(edges, memoryId, tagId, 'tagged');
    }
    for (const symbol of arrayOfStrings(record.symbols)) {
      const symbolId = 'symbol:' + symbol;
      addNode(nodes, { id: symbolId, type: 'symbol', label: symbol });
      addEdge(edges, memoryId, symbolId, 'mentions_symbol');
    }
    for (const lock of arrayOfStrings(record.locks)) {
      const lockId = 'lock:' + lock;
      addNode(nodes, { id: lockId, type: 'lock', label: lock });
      addEdge(edges, memoryId, lockId, 'mentions_lock');
    }
  }

  const taskStore = readJsonFile(path.join(atomicDir, 'swarm-tasks.json'), { tasks: [] });
  const tasks = Array.isArray(taskStore) ? taskStore : Array.isArray(taskStore.tasks) ? taskStore.tasks : [];
  sourceCounts.swarmTasks = tasks.length;
  for (const task of tasks) {
    const id = Number(task?.id);
    if (!Number.isInteger(id)) continue;
    const taskId = 'task:' + id;
    addNode(nodes, { id: taskId, type: 'task', source: 'swarm-tasks', label: String(task.subject || id), status: task.status || 'pending', verifiedCompletion: task.completion?.verified ?? null });
    if (task.claimedBy) {
      const workerId = 'agent:' + task.claimedBy;
      addNode(nodes, { id: workerId, type: 'agent', label: String(task.claimedBy) });
      addEdge(edges, workerId, taskId, 'claimed');
    }
  }

  const taskEvents = readJsonlTailMany('swarm-tasks-ledger.jsonl', atomicDirs);
  sourceCounts.swarmTaskLedger = taskEvents.length;
  for (const event of taskEvents.slice(-limit)) {
    if (!event || typeof event !== 'object') continue;
    const id = event.id ?? event.taskId;
    if (id === undefined) continue;
    const taskId = 'task:' + id;
    addNode(nodes, { id: taskId, type: 'task', label: String(id) });
    if (event.tool) addEdge(edges, 'ledger:swarm-tasks', taskId, String(event.tool));
    addNode(nodes, { id: 'ledger:swarm-tasks', type: 'ledger', label: 'swarm-tasks-ledger.jsonl' });
  }

  const lessons = readJsonlTailMany('lesson-ledger.jsonl', atomicDirs);
  sourceCounts.lessons = lessons.length;
  for (const lesson of lessons) {
    const recordSha256 = verifyObjectHash(lesson, 'recordSha256');
    if (!recordSha256) continue;
    const lessonId = String(lesson.lessonId || 'lesson:' + recordSha256);
    addNode(nodes, { id: lessonId, type: 'lesson', source: 'lesson-ledger', verified: true, label: lessonId, decision: lesson.decision, recordSha256 });
    const file = lesson.operator?.file;
    if (typeof file === 'string' && file) {
      const fileId = 'file:' + file;
      addNode(nodes, { id: fileId, type: 'file', label: file });
      addEdge(edges, lessonId, fileId, 'touches_file');
      lessonFacts.push({
        id: lessonId,
        file,
        ts: timestampMs(lesson.context?.ts) ?? timestampMs(lesson.ts) ?? timestampMs(lesson.at) ?? timestampMs(lesson.context?.at),
        decision: lesson.decision ?? null,
      });
    }
    for (const gate of arrayOfStrings(lesson.effect?.gatesFlipped)) {
      const gateId = 'gate:' + gate;
      addNode(nodes, { id: gateId, type: 'gate', label: gate });
      addEdge(edges, lessonId, gateId, 'flipped_gate');
    }
  }

  const emergence = readJsonlTailMany('emergence-feed.jsonl', atomicDirs);
  sourceCounts.emergence = emergence.length;
  for (const event of emergence) {
    const recordSha = verifyEmergenceRecord(event);
    if (!recordSha) continue;
    const eventId = 'event:' + recordSha;
    addNode(nodes, { id: eventId, type: 'emergence_event', source: 'emergence-feed', verified: true, label: String(event.kind || event.op || 'event'), kind: event.kind, op: event.op, file: event.file, recordSha });
    if (typeof event.file === 'string' && event.file) {
      const fileId = 'file:' + event.file;
      addNode(nodes, { id: fileId, type: 'file', label: event.file });
      addEdge(edges, eventId, fileId, 'observed_file');
      pushMapList(fileEventFacts, event.file, {
        id: eventId,
        file: event.file,
        ts: timestampMs(event.ts) ?? timestampMs(event.at),
        recordSha,
      });
    }
    const matches = Array.isArray(event.semanticMemoryRecall?.matches) ? event.semanticMemoryRecall.matches : [];
    for (const match of matches) {
      if (!match || typeof match !== 'object') continue;
      const target = match.source === 'semantic-memory-ledger' && match.id ? 'memory:' + match.id : match.source === 'lesson-ledger' && match.id ? String(match.id) : '';
      if (target) addEdge(edges, eventId, target, 'recalled');
    }
  }

  sourceCounts.causalEdges = addTemporalCausalEdges(edges, fileEventFacts, lessonFacts);
  const filtered = graphFilter(nodes, edges, args.query);
  const nodeCandidates = filtered.nodes.sort((a, b) => String(a.id).localeCompare(String(b.id)));
  const edgeCandidates = filtered.edges
    .sort((a, b) => (a.from + a.type + a.to).localeCompare(b.from + b.type + b.to))
    .slice(0, limit * 2);
  let sortedNodes = nodeCandidates.slice(0, limit);
  if (args.query && edgeCandidates.length > 0) {
    const byId = new Map(nodeCandidates.map((node) => [node.id, node]));
    const selected = [];
    const seen = new Set();
    const addEndpoint = (id) => {
      if (seen.has(id) || selected.length >= limit) return;
      const node = byId.get(id);
      if (!node) return;
      seen.add(id);
      selected.push(node);
    };
    for (const edge of edgeCandidates) {
      addEndpoint(edge.from);
      addEndpoint(edge.to);
      if (selected.length >= limit) break;
    }
    for (const node of nodeCandidates) {
      if (selected.length >= limit) break;
      addEndpoint(node.id);
    }
    sortedNodes = selected;
  }
  const nodeIds = new Set(sortedNodes.map((node) => node.id));
  const sortedEdges = edgeCandidates.filter((edge) => nodeIds.has(edge.from) && nodeIds.has(edge.to));
  const graph = { nodes: sortedNodes, edges: sortedEdges, sourceCounts };
  return {
    graphSha256: graphSha(graph),
    nodeCount: sortedNodes.length,
    edgeCount: sortedEdges.length,
    truncated: filtered.nodes.length > sortedNodes.length || filtered.edges.length > sortedEdges.length,
    sources: sourceCounts,
    nodes: sortedNodes,
    edges: sortedEdges,
  };
}

function queryJSONLFallback(args) {
  if (!fs.existsSync(LEDGER_FILE)) return [];
  const lines = fs.readFileSync(LEDGER_FILE, 'utf-8').split('\n').filter(Boolean);
  const results = [];

  for (const line of lines) {
    try {
      const entry = JSON.parse(line);
      let matches = true;

      if (args.query) {
        const terms = args.query.toLowerCase().split(/\s+/).filter(Boolean);
        const haystack = entry.intent.toLowerCase();
        if (!terms.every(t => haystack.includes(t))) {
          matches = false;
        }
      }
      if (args.tag && !(entry.tags && entry.tags.includes(args.tag))) {
        matches = false;
      }
      if (args.file && !(entry.files && entry.files.includes(args.file))) {
        matches = false;
      }
      if (args.taskId && !(entry.tasks && entry.tasks.map(String).includes(String(args.taskId)))) {
        matches = false;
      }
      if (args.symbol && !(entry.symbols && entry.symbols.includes(args.symbol))) {
        matches = false;
      }
      if (args.lockId && !(entry.locks && entry.locks.includes(args.lockId))) {
        matches = false;
      }

      if (matches) results.push(entry);
    } catch (e) {}
  }
  results.sort((a, b) => new Date(b.at) - new Date(a.at));
  return results;
}

function ok(payload) {
  return { content: [{ type: 'text', text: JSON.stringify(payload, null, 2) }] };
}

function fail(error) {
  return { content: [{ type: 'text', text: JSON.stringify({ ok: false, error: String(error) }, null, 2) }], isError: true };
}

server.registerTool(
  'memory_record',
  {
    title: 'Record a semantic memory with verifiable intent',
    description: 'Save a structural explanation of WHY a code change, task, or lock was made. This connects the append-only ledger with cognitive rationale, creating a semantic graph of the system evolution.',
    inputSchema: {
      intent: z.string().min(10),
      relatedFiles: z.array(z.string()).optional(),
      relatedTaskIds: z.array(z.union([z.string(), z.number()])).optional(),
      tags: z.array(z.string()).optional(),
      symbols: z.array(z.string()).optional(),
      gitCommit: z.string().optional(),
      lockIds: z.array(z.string()).optional()
    }
  },
  async (args) => {
    try {
      const entry = {
        at: new Date().toISOString(),
        tool: 'memory_record',
        intent: args.intent,
        files: args.relatedFiles || [],
        tasks: (args.relatedTaskIds || []).map(String),
        tags: args.tags || [],
        symbols: args.symbols || [],
        gitCommit: args.gitCommit || null,
        locks: args.lockIds || []
      };
      
      const entryStr = JSON.stringify(entry);
      const hash = crypto.createHash('sha256').update(entryStr).digest('hex');
      const finalEntry = JSON.stringify({ ...entry, hash });
      
      fs.appendFileSync(LEDGER_FILE, finalEntry + '\n');
      insertMemoryToDb({ ...entry, hash });

      // HONESTY (memory P0): verify the write ACTUALLY landed. appendFileSync succeeding does NOT
      // guarantee durability under every host wiring (a connected server rooted at an ephemeral cwd,
      // or a harness stub, can return ok+hash without persisting). Read back the ledger and REFUSE to
      // claim success if our entry is absent — never fake a recorded memory (the honesty layer this
      // substrate exists to provide).
      let persisted = false;
      try { persisted = fs.readFileSync(LEDGER_FILE, 'utf8').includes(hash); } catch { /* read-back failed */ }
      if (!persisted) {
        return ok({ ok: false, hash, recordedAt: entry.at, ledgerFile: LEDGER_FILE,
          warning: 'memory_record write did NOT verify on read-back — the entry is not confirmed durable at ' + LEDGER_FILE + '. Do not claim the memory was recorded; the host wiring (ephemeral cwd / stub) likely swallowed the write.' });
      }
      return ok({ ok: true, hash, recordedAt: entry.at, ledgerFile: LEDGER_FILE });
    } catch (e) {
      return fail(e);
    }
  }
);

server.registerTool(
  'memory_query',
  {
    title: 'Query the semantic memory ledger',
    description: 'Search past intents by keyword, tag, file path, symbol, task ID, or lock ID.',
    inputSchema: {
      query: z.string().optional(),
      tag: z.string().optional(),
      file: z.string().optional(),
      taskId: z.union([z.string(), z.number()]).optional(),
      symbol: z.string().optional(),
      lockId: z.string().optional(),
      limit: z.number().int().positive().default(50).optional()
    }
  },
  async (args) => {
    try {
      const limit = args.limit ?? 50;
      const results = db ? querySQLite(args) : queryJSONLFallback(args);
      const capped = results.slice(0, limit);
      return ok({ ok: true, results: capped });
    } catch (e) {
      return fail(e);
    }
  }
);

server.registerTool(
  'memory_graph',
  {
    title: 'Unified atomic memory graph',
    description: 'Build a bounded, receipt-hashed graph from verified semantic memory, swarm tasks, lesson-ledger, and emergence-feed records. This is a local cortex query: no network, no spawn, no unverified memory claims.',
    inputSchema: {
      query: z.string().optional(),
      limit: z.number().int().positive().max(1000).default(200).optional()
    }
  },
  async (args) => {
    try {
      return ok({ ok: true, ...buildMemoryGraph(args) });
    } catch (e) {
      return fail(e);
    }
  }
);

server.registerTool(
  'minimal_recomputable_disproof',
  {
    title: 'Minimal recomputable disproof — neuro-symbolic (1-minimal UNSAT core + byte-level witness)',
    description: 'THE emergent fusion (PART D A-G3 + E2): stamp the delta-debugged 1-MINIMAL failing subset into the recomputable byte-level witness. Both FINER than a plain UNSAT-core (1-minimal) AND RICHER (actual rejected bytes + per-fact digests). Provide failingSubsets (pre-evaluated subset->fails) so the tool computes the minimal core in-process with no spawn; an unevaluated subset is conservatively treated as failing only when it equals the full obligation set.',
    inputSchema: {
      witness: z.record(z.any()).describe('the recomputable byte-level witness (removedRegion + counterexample facts)'),
      obligations: z.array(z.string()).min(1).describe('the full enforced obligation set under disproof'),
      failingSubsets: z.array(z.object({ subset: z.array(z.string()), fails: z.boolean() })).optional().describe('pre-evaluated oracle: which subsets still fail. Omit to assume only the full set is known to fail.')
    }
  },
  async (args) => {
    try {
      const evalMap = new Map();
      if (Array.isArray(args.failingSubsets)) {
        for (const fs of args.failingSubsets) {
          evalMap.set([...fs.subset].sort().join('||'), !!fs.fails);
        }
      }
      const fails = (subset) => {
        const key = [...subset].sort().join('||');
        if (evalMap.has(key)) return evalMap.get(key);
        return subset.length >= args.obligations.length;
      };
      const result = minimalRecomputableDisproof(args.witness, args.obligations, fails);
      return ok({ ok: true, ...result });
    } catch (e) {
      return fail(e);
    }
  }
);

server.registerTool(
  'truth_funnel_gate',
  {
    title: 'Universal truth funnel — P9 verifier-gated admission (neuro-symbolic)',
    description: "PARADIGM PART F (P9): a candidate answer is admitted IFF the supplied deterministic verifier accepts every unit. Returns {submit, unjudged, rejected[], accepted[]}. A non-deterministic or absent verifier ABSTAINS (unjudged=true) — the funnel never fakes a verdict (Rice/honesty). HONESTY (F4): 'wrong answers are unrepresentable' holds ONLY relative to the verifier the caller supplies — the funnel never overrides it and never invents a verdict, but it does NOT cryptographically bind the verifier's identity, so the guarantee is CONDITIONAL on the caller passing the genuine deterministic verifier (a forged/buggy verifier is not detected here).",
    inputSchema: {
      units: z.array(z.object({ id: z.union([z.string(), z.number()]), verdict: z.enum(['accept', 'reject']) })).describe('the deterministic verifier verdict per unit'),
      deterministic: z.boolean().describe('whether the verifier is deterministic; false => the funnel ABSTAINS (unjudged), never fakes a verdict')
    }
  },
  async (args) => {
    try {
      const verification = { units: args.units, deterministic: args.deterministic };
      const gate = funnelGate(verification);
      const parts = decompose(verification);
      return ok({ ok: true, ...gate, accepted: parts.accepted, rejected: parts.rejected });
    } catch (e) { return fail(e); }
  }
);

server.registerTool(
  'friction_route_batch',
  {
    title: 'Stigmergic friction-routed multi-agent task assignment (neuro-symbolic coordination, capability c*)',
    description: "PARADIGM PART D.3 (the stigmergic move): assign each task to the least-friction agent while SPREADING concurrent work that touches the same invariant across different agents (rising collision penalty). Produces an assignment whose tasks tend to touch disjoint agents per invariant — the precondition the (e) algebra needs to prove merges confluent (E1). Friction is derived from a wall-event stream (agent x invariant hits); the recomputable pheromone digests make the signal VERIFIABLE. The never-before-done capability: friction routing + obligation-preserving confluence.",
    inputSchema: {
      tasks: z.array(z.object({ id: z.string().optional(), invariants: z.array(z.string()) })).describe('tasks to assign; each lists the invariantIds it touches'),
      agents: z.array(z.string()).describe('candidate agents'),
      events: z.array(z.object({ agent: z.string(), invariantId: z.string(), seq: z.number().optional(), witness: z.any().optional() })).describe('friction history: which agent hit which invariant (wall events)'),
      window: z.number().int().positive().optional().describe('rolling window of recent events that count as recent friction (default 10)'),
      penaltyStep: z.number().int().positive().optional().describe('collision penalty step per reuse of an agent on the same invariant (default 100)')
    }
  },
  async (args) => {
    try {
      const state = buildFrictionLedger(args.events || [], { window: args.window });
      const assignment = routeBatch(args.tasks, args.agents, state, { penaltyStep: args.penaltyStep });
      return ok({ ok: true, assignment, totalEvents: state.totalEvents, window: state.window });
    } catch (e) { return fail(e); }
  }
);

server.registerTool(
  'wavefront_of',
  {
    title: 'Concurrent wavefront of a routed assignment (E1 fusion input, neuro-symbolic c*)',
    description: "PARADIGM PART D.3/E1: given a friction-routed task->agent assignment (e.g. from friction_route_batch), derive the CONCURRENT WAVEFRONT — the set of in-flight edits, one per agent (an agent's later tasks serialize behind its first). This wavefront is exactly what the (e) algebra machine-checks for confluence + obligation-preservation. The c* capability: provably-confluent, friction-routed multi-agent editing — exists in NEITHER atomic-alone (proves confluence but does not route) NOR Nidus-alone (routes but cannot prove confluence).",
    inputSchema: {
      assignment: z.array(z.object({ taskId: z.union([z.string(), z.number()]).optional(), agent: z.string() })).describe('routed assignment (task->agent), e.g. output of friction_route_batch')
    }
  },
  async (args) => {
    try {
      const wave = wavefrontOf(args.assignment);
      return ok({ ok: true, wavefront: wave, width: wave.length, agents: wave.map((w) => w.agent) });
    } catch (e) { return fail(e); }
  }
);

async function run() {
  syncDatabase();
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

run().catch(console.error);
