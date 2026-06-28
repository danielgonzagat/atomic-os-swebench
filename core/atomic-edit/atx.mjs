#!/usr/bin/env node
/**
 * atx.mjs — the atomic-by-construction CLI, UNIFIED across all atomic MCP servers (gap #1).
 *
 * Every command routes through an atomic MCP server's tools/call — so every op goes through that
 * server's substrate (atomic-edit: atomicWrite + gate floor + receipts; siblings: their honesty
 * layers). There is NO weaker duplicated path and NO escape hatch.
 *
 * Atomic-by-construction guarantees (enforced here, proven in gates/atx-atomic-cli.proof.mjs):
 *   (1) CLOSED command whitelist — add a command ONLY by extending COMMANDS. Unknown → refused (2).
 *   (2) NO escape hatch — --force/--raw/--unsafe/--no-gates/--bypass/--no-receipt refused anywhere.
 *   (3) NO direct fs/exec mutation — atx spawns ONLY MCP servers (atomic-call for edit, mcpCall for
 *       siblings) with whitelisted tool names; it never writes a file or runs a shell on its own.
 *   (4) Every command surfaces the MCP tool's receipt/content.
 *
 * Cross-server routing:
 *   - edit-server commands (read/edit/exec/...) use atomic-call.mjs (handles dist build + bare call).
 *   - sibling commands (memory/sentinel/fetch/funnel) use mcpCall() — a minimal JSON-RPC client that
 *     performs the mandatory initialize → notifications/initialized → tools/call handshake.
 *
 * Usage: atx <command> [args...]   (atx read f.ts ; atx sentinel status ; atx memory query X ; atx help)
 */
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import * as path from 'node:path';

const dir = path.dirname(fileURLToPath(import.meta.url));          // core/atomic-edit
const repoRoot = path.resolve(dir, '..', '..');                       // atomic-os-swebench
const atomicCall = path.join(dir, 'atomic-call.mjs');
const EDIT_ATOMIC_CALL_TIMEOUT_MS = 180_000;
const siblingRoot = path.join(repoRoot, 'vendor', 'mcp-siblings'); // atomic-os-swebench/vendor/mcp-siblings

// MCP server scripts for cross-server commands.
const SERVERS = {
  memory: path.join(siblingRoot, 'atomic-memory', 'server.mjs'),
  sentinel: path.join(siblingRoot, 'atomic-sentinel', 'server.mjs'),
  swarm: path.join(siblingRoot, 'atomic-swarm', 'server.mjs'),
};

// Minimal JSON-RPC MCP client: initialize → notifications/initialized → tools/call.
async function mcpCall(serverScript, tool, args) {
  if (!serverScript) throw new Error(`unknown MCP server for tool ${tool}`);
  return new Promise((resolve, reject) => {
    const p = spawn(process.execPath, [serverScript], {
      cwd: repoRoot,
      env: {
        ...process.env,
        ATOMIC_REPO_ROOT: process.env.ATOMIC_REPO_ROOT || repoRoot,
        ATOMIC_SWARM_REPO_ROOT: process.env.ATOMIC_SWARM_REPO_ROOT || process.env.ATOMIC_REPO_ROOT || repoRoot,
      },
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    let buf = '';
    let nextId = 1;
    const pending = new Map();
    const send = (o) => p.stdin.write(JSON.stringify(o) + '\n');
    const call = (method, params) => {
      const id = nextId++; send({ jsonrpc: '2.0', id, method, params });
      return new Promise((res, rej) => pending.set(id, { res, rej }));
    };
    let initialized = false;
    const timer = setTimeout(() => { try { p.kill(); } catch {} reject(new Error('mcpCall timeout')); }, 30000);
    p.stdout.on('data', (d) => {
      buf += d.toString();
      const lines = buf.split('\n'); buf = lines.pop();
      for (const line of lines) {
        if (!line.startsWith('{')) continue;
        let msg; try { msg = JSON.parse(line); } catch { continue; }
        if (msg.id && pending.has(msg.id)) {
          const { res, rej } = pending.get(msg.id); pending.delete(msg.id);
          msg.error ? rej(new Error(JSON.stringify(msg.error))) : res(msg.result);
        }
        if (msg.result && msg.result.capabilities && !initialized) {
          initialized = true;
          send({ jsonrpc: '2.0', method: 'notifications/initialized' });
          call('tools/call', { name: tool, arguments: args })
            .then((r) => { clearTimeout(timer); const txt = (r.content || []).map((c) => c.text || '').join('\n'); try { p.kill(); } catch {} resolve(txt || JSON.stringify(r)); })
            .catch((e) => { clearTimeout(timer); try { p.kill(); } catch {} reject(e); });
        }
      }
    });
    p.on('exit', (c) => { if (!initialized) { clearTimeout(timer); reject(new Error(`MCP server exited before initialize (code=${c})`)); } });
    call('initialize', { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'atx', version: '1' } }).catch((e) => { clearTimeout(timer); reject(e); });
  });
}

function parseJson(text, fallback = {}) {
  if (!text) return fallback;
  try { return JSON.parse(text); } catch { return fallback; }
}

function subcommand(name, value, allowed) {
  if (allowed.includes(value)) return value;
  throw new Error(`${name} subcommand ${value || '(empty)'} is not permitted; allowed: ${allowed.join(', ')}`);
}

function lockCommand(a) {
  const sub = subcommand('lock', a[0] || 'status', ['status', 'acquire', 'heartbeat', 'steal', 'release']);
  if (sub === 'status') return { tool: 'swarm_lock_status', args: {} };
  if (sub === 'acquire') return { tool: 'swarm_lock_acquire', args: parseJson(a[1], { frontId: a[1], owner: a[2], objective: a.slice(3).join(' ') || 'atx lock acquire' }) };
  if (sub === 'heartbeat') return { tool: 'swarm_lock_heartbeat', args: parseJson(a[1], { frontId: a[1], owner: a[2] }) };
  if (sub === 'steal') return { tool: 'swarm_lock_steal', args: parseJson(a[1], { frontId: a[1], newOwner: a[2], objective: a.slice(3).join(' ') || undefined }) };
  return { tool: 'swarm_lock_release', args: parseJson(a[1], { frontId: a[1], owner: a[2] }) };
}

function taskCommand(a) {
  const sub = subcommand('task', a[0] || 'list', ['list', 'create', 'update']);
  if (sub === 'list') return { tool: 'swarm_task_list', args: {} };
  if (sub === 'create') return { tool: 'swarm_task_create', args: parseJson(a[1], { subject: a.slice(1).join(' ') }) };
  return { tool: 'swarm_task_update', args: parseJson(a[1], { id: Number(a[1]), status: a[2], description: a.slice(3).join(' ') || undefined }) };
}

function sentinelCommand(a) {
  const sub = subcommand('sentinel', a[0] || 'status', ['status', 'sweep', 'clear']);
  if (sub === 'sweep') return { tool: 'sentinel_sweep', args: {} };
  if (sub === 'clear') return { tool: 'sentinel_clear_alerts', args: { scope: a[1] || 'all' } };
  return { tool: 'sentinel_status', args: {} };
}

function funnelArgs(a) {
  const parsed = parseJson(a[0], null);
  if (parsed) return parsed;
  return {
    deterministic: true,
    units: a.map((token, index) => {
      const [verdict, id] = String(token).split(':');
      return { id: id || String(index + 1), verdict: verdict === 'reject' ? 'reject' : 'accept' };
    }),
  };
}

function verifyCommand(a) {
  const scope = subcommand('verify', a[0] || 'mcp-controlled', ['mcp-controlled', 'whole-host']);
  return { tool: 'atomic_y_certificate', args: { scope } };
}

function reentryCommand(a) {
  return { tool: 'atomic_host_reentry_receipt', args: a.length > 0 ? { command: a } : {} };
}

// CLOSED whitelist: command -> { server, tool, map|resolve }. Extend ONLY here.
const COMMANDS = {
  // atomic-edit server (via atomic-call — handles dist build + bare tools/call)
  read:      { server: 'edit', tool: 'code_readcode',         map: (a) => ({ path: a[0] }) },
  outline:   { server: 'edit', tool: 'code_outline',          map: (a) => ({ path: a[0] }) },
  symbol:    { server: 'edit', tool: 'code_read_symbol',      map: (a) => ({ path: a[0], symbol: a[1] }) },
  exec:      { server: 'edit', tool: 'atomic_exec',           map: (a) => ({ cwd: a[0], command: a.slice(1).join(' ') }) },
  edit:      { server: 'edit', tool: 'atomic_replace_text',   map: (a) => ({ file: a[0], oldText: a[1], newText: a[2] }) },
  locate:    { server: 'edit', tool: 'atomic_locate',         map: (a) => ({ file: a[0], anchor: a[1] }) },
  converge:  { server: 'edit', tool: 'atomic_converge',       map: (a) => ({ files: a }) },
  verify:    { server: 'edit', resolve: verifyCommand },
  reentry:   { server: 'edit', resolve: reentryCommand },
  evolve:    { server: 'edit', tool: 'atomic_self_evolution', map: (a) => parseJson(a[0], { intent: a.join(' ') }) },
  pulse:     { server: 'edit', tool: 'atomic_emergence_cycle', map: (a) => parseJson(a[0], { mode: a[0] || 'report' }) },
  // sibling servers (via mcpCall handshake)
  memory:    { server: 'memory', tool: 'memory_query',        map: (a) => ({ query: a.join(' ') }) },
  graph:     { server: 'memory', tool: 'memory_graph',        map: (a) => parseJson(a[0], { query: a.join(' ') || undefined }) },
  record:    { server: 'memory', tool: 'memory_record',       map: (a) => parseJson(a[0], { intent: a.join(' ') }) },
  funnel:    { server: 'memory', tool: 'truth_funnel_gate',   map: funnelArgs },
  route:     { server: 'memory', tool: 'friction_route_batch', map: (a) => parseJson(a[0], {}) },
  wavefront: { server: 'memory', tool: 'wavefront_of',        map: (a) => parseJson(a[0], {}) },
  search:    { server: 'swarm', tool: 'swarm_web_search',     map: (a) => ({ query: a.join(' ') }) },
  fetch:     { server: 'swarm', tool: 'swarm_fetch',          map: (a) => ({ url: a[0] }) },
  lock:      { server: 'swarm', resolve: lockCommand },
  task:      { server: 'swarm', resolve: taskCommand },
  swarm:     { server: 'swarm', tool: 'swarm_status',         map: () => ({}) },
  sentinel:  { server: 'sentinel', resolve: sentinelCommand },
};

const FORBIDDEN_FLAGS = ['--force', '--raw', '--unsafe', '--no-gates', '--bypass', '--no-receipt'];

function refuse(msg) { process.stderr.write(`atx refused: ${msg}\n`); process.exit(2); }

const argv = process.argv.slice(2);
for (const f of FORBIDDEN_FLAGS) {
  if (argv.includes(f)) refuse(`flag ${f} is not permitted — atx is atomic-by-construction (no escape hatch; every op is a receipted, gate-checked MCP tool call).`);
}

const cmd = argv[0];
if (!cmd || cmd === 'help' || cmd === '--help' || cmd === '-h') {
  process.stdout.write(
    'atx — atomic-by-construction CLI (unified across all atomic MCP servers). Every command routes\n' +
    'through an MCP server substrate (atomicWrite/gates/receipts) — no weaker duplicated path.\n' +
    'Commands (closed whitelist): ' + Object.keys(COMMANDS).join(', ') + '\n' +
    'No --force/--raw/--bypass: unknown commands and escape-hatch flags are refused (exit 2).\n',
  );
  process.exit(cmd ? 0 : 2);
}

const spec = COMMANDS[cmd];
if (!spec) refuse(`unknown command "${cmd}" — atx dispatches only the closed whitelist: ${Object.keys(COMMANDS).join(', ')}.`);

let resolved;
try {
  const args = argv.slice(1);
  resolved = spec.resolve ? spec.resolve(args) : { tool: spec.tool, args: spec.map(args) };
} catch (e) {
  refuse(e instanceof Error ? e.message : String(e));
}

const serverName = resolved.server || spec.server;
const tool = resolved.tool;
const toolArgs = resolved.args;

if (serverName === 'edit') {
  // atomic-edit server via atomic-call (builds dist + bare tools/call).
  const result = spawnSync(process.execPath, [atomicCall, tool, JSON.stringify(toolArgs)], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    maxBuffer: 64 * 1024 * 1024,
    timeout: EDIT_ATOMIC_CALL_TIMEOUT_MS,
    env: {
      ...process.env,
      ATOMIC_DISABLE_HOT_RELOAD: process.env.ATOMIC_DISABLE_HOT_RELOAD || '1',
    },
  });
  if (result.error) {
    process.stderr.write('atx edit-server call failed: ' + result.error.message + '\n');
    process.exit(1);
  }
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  process.exit(result.status ?? 1);
}

// Sibling server via the MCP handshake client.
const serverScript = SERVERS[serverName];
if (!serverScript) refuse(`no MCP server mapped for command "${cmd}".`);
try {
  const out = await mcpCall(serverScript, tool, toolArgs);
  process.stdout.write(out + '\n');
  process.exit(0);
} catch (e) {
  process.stderr.write(`atx ${cmd} failed: ${e.message}\n`);
  process.exit(1);
}
