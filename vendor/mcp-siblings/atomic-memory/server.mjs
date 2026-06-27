#!/usr/bin/env node
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import os from 'node:os';

const server = new McpServer({ name: 'atomic-memory', version: '1.0.0' });
const REPO_ROOT = process.env.ATOMIC_SWARM_REPO_ROOT || process.cwd();
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
    wheres.push('m.intent LIKE ?');
    params.push(`%${args.query}%`);
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

function queryJSONLFallback(args) {
  if (!fs.existsSync(LEDGER_FILE)) return [];
  const lines = fs.readFileSync(LEDGER_FILE, 'utf-8').split('\n').filter(Boolean);
  const results = [];

  for (const line of lines) {
    try {
      const entry = JSON.parse(line);
      let matches = true;

      if (args.query && !entry.intent.toLowerCase().includes(args.query.toLowerCase())) {
        matches = false;
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
      
      return ok({ ok: true, hash, recordedAt: entry.at });
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

async function run() {
  syncDatabase();
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

run().catch(console.error);
