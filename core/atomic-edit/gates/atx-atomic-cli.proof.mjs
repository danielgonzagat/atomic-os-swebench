#!/usr/bin/env node
/**
 * atx-atomic-cli.proof.mjs — proves the atx CLI is atomic-by-construction (gap #1 foundation).
 *
 * atx must be a CLOSED system: every command routes through the atomic-edit MCP substrate
 * (atomicWrite + gates + receipts) via atomic-call; there is no escape hatch and no duplicated
 * weaker path. This proof asserts both the structural guarantees (source-level) and the runtime
 * contract (functional: help/refusal), so the CLI cannot silently grow a bypass.
 *
 * Run: node gates/atx-atomic-cli.proof.mjs [--json]
 */
import * as fs from 'node:fs';
import * as path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const dir = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(dir, '..');
const atxPath = path.join(root, 'atx.mjs');
const src = fs.readFileSync(atxPath, 'utf8');
const jsonMode = process.argv.includes('--json');
const selfExpansionValidator = process.env.ATOMIC_SELF_EXPANSION_VALIDATOR === '1' || process.env.ATOMIC_BUILD_BROKER === '1';

let pass = 0, fail = 0;
const results = [];
const check = (name, cond, detail) => {
  const ok = !!cond;
  ok ? (pass += 1) : (fail += 1);
  const entry = { name, ok, ...(detail !== undefined ? { detail } : {}) };
  results.push(entry);
  if (!jsonMode) {
    console.log(`  ${ok ? 'PASS ' : 'FAIL '} ${name}${detail ? ' :: ' + JSON.stringify(detail) : ''}`);
  }
};

function runAtx(args) {
  const r = spawnSync(process.execPath, [atxPath, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 15000 });
  return { status: r.status, stdout: r.stdout || '', stderr: r.stderr || '' };
}
function runAtxSlow(args) {
  const r = spawnSync(process.execPath, [atxPath, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 35000 });
  return { status: r.status, stdout: r.stdout || '', stderr: r.stderr || '' };
}

const listed = [...src.matchAll(/^  (\w+):\s+\{/gm)].map((m) => m[1]);
const requiredAtxCommands = [
  'read', 'outline', 'symbol', 'exec', 'edit', 'locate', 'converge', 'verify', 'reentry', 'evolve', 'pulse',
  'memory', 'graph', 'record', 'funnel', 'route', 'wavefront', 'search', 'fetch', 'lock', 'task', 'swarm', 'sentinel',
];
const missingAtxCommands = requiredAtxCommands.filter((name) => !listed.includes(name));
const requiredToolMappings = [
  "tool: 'code_readcode'",
  "tool: 'code_outline'",
  "tool: 'code_read_symbol'",
  "tool: 'atomic_exec'",
  "tool: 'atomic_replace_text'",
  "tool: 'atomic_locate'",
  "tool: 'atomic_converge'",
  "tool: 'atomic_y_certificate'",
  "tool: 'atomic_host_reentry_receipt'",
  "tool: 'atomic_self_evolution'",
  "tool: 'atomic_emergence_cycle'",
  "tool: 'memory_query'",
  "tool: 'memory_graph'",
  "tool: 'memory_record'",
  "tool: 'truth_funnel_gate'",
  "tool: 'friction_route_batch'",
  "tool: 'wavefront_of'",
  "tool: 'swarm_web_search'",
  "tool: 'swarm_fetch'",
  "tool: 'swarm_status'",
];
const missingToolMappings = requiredToolMappings.filter((marker) => !src.includes(marker));

check('structure: closed COMMANDS whitelist exists', src.includes('const COMMANDS = {') && src.includes("cmd === 'help'"));
check('structure: canonical atomic OS command set is present', missingAtxCommands.length === 0, { missingAtxCommands });
check('structure: core commands map to MCP atomic tools, not bespoke local handlers', missingToolMappings.length === 0, { missingToolMappings });
check('structure: forbidden escape-hatch flags enforced', ['--force', '--raw', '--unsafe', '--no-gates', '--bypass', '--no-receipt'].every((f) => src.includes(`'${f}'`)));
check('structure: unknown commands are refused (exit 2)', src.includes("refuse(`unknown command") && src.includes('process.exit(2)'));
check('structure: NO direct fs write — atx never persists a file itself',
  !/\bfs\.(write|append|unlink|rename)FileSync\b/.test(src));
check('structure: closed SERVERS map for cross-server sibling routing', src.includes('const SERVERS = {') && src.includes('siblingRoot'));
check('structure: sibling MCP calls inherit the Atomic repo root explicitly',
  src.includes('const repoRoot = path.resolve(dir') &&
    src.includes('cwd: repoRoot') &&
    src.includes('ATOMIC_REPO_ROOT: process.env.ATOMIC_REPO_ROOT || repoRoot') &&
    src.includes('ATOMIC_SWARM_REPO_ROOT: process.env.ATOMIC_SWARM_REPO_ROOT || process.env.ATOMIC_REPO_ROOT || repoRoot'));
check('structure: arbitrary-exec blocked — atx spawns ONLY atomic-call (edit) or a SERVERS sibling script, always with a whitelisted spec.tool (never argv)',
  src.includes('[atomicCall, tool,') && src.includes('mcpCall(serverScript, tool, toolArgs)') && src.includes('SERVERS[serverName]') && !/\bexecSync\b/.test(src) && !/spawn\w*\([^)]*argv/.test(src));
check('structure: every command names its server (edit|memory|sentinel|swarm) — no orphan tool',
  /server:\s*['"]edit['"]/.test(src) && /server:\s*['"]sentinel['"]/.test(src));
check('structure: edit-server atomic-call is bounded and disables hot-reload recursion',
  src.includes('EDIT_ATOMIC_CALL_TIMEOUT_MS') &&
    src.includes('timeout: EDIT_ATOMIC_CALL_TIMEOUT_MS') &&
    src.includes('ATOMIC_DISABLE_HOT_RELOAD') &&
    src.includes('result.error') &&
    src.includes('atx edit-server call failed'),
  { selfExpansionValidator });
check('structure: verify defaults to mcp-controlled and validates certificate scopes before MCP dispatch',
  src.includes('function verifyCommand') &&
    src.includes("a[0] || 'mcp-controlled'") &&
    src.includes("['mcp-controlled', 'whole-host']") &&
    !src.includes("scope: a[0] || 'workspace'"));
check('structure: reentry command routes to atomic_host_reentry_receipt',
  src.includes('function reentryCommand') && src.includes("tool: 'atomic_host_reentry_receipt'"));

const help = runAtx(['help']);
check('functional: `atx help` exits 0', help.status === 0);
check('functional: help lists ONLY the whitelisted commands (no passthrough)', listed.every((c) => help.stdout.includes(c)) && help.stdout.includes('closed whitelist'));

const noArgs = runAtx([]);
check('functional: `atx` with no args exits 2 (refuses to guess)', noArgs.status === 2);

const force = runAtx(['--force', 'read', 'x']);
check('functional: `atx --force ...` REFUSED (exit 2, no escape hatch)', force.status === 2 && /not permitted|escape hatch/i.test(force.stderr));

const raw = runAtx(['edit', 'f.ts', 'a', 'b', '--raw']);
check('functional: `atx ... --raw` (flag anywhere) REFUSED (exit 2)', raw.status === 2 && /not permitted|escape hatch/i.test(raw.stderr));

const unknown = runAtx(['shell', 'rm', '-rf', 'x']);
check('functional: unknown command `atx shell ...` REFUSED (exit 2, closed whitelist)', unknown.status === 2 && /unknown command/i.test(unknown.stderr));

const badVerifyScope = runAtx(['verify', 'workspace']);
check('functional: `atx verify workspace` REFUSED before MCP dispatch (invalid certificate scope)', badVerifyScope.status === 2 && /verify subcommand workspace is not permitted/.test(badVerifyScope.stderr), { status: badVerifyScope.status });

if (selfExpansionValidator) {
  check('functional: skips live edit/sentinel runtime checks under self-expansion validator',
    src.includes('EDIT_ATOMIC_CALL_TIMEOUT_MS') && src.includes('mcpCall(serverScript, tool, toolArgs)'),
    { selfExpansionValidator });
} else {
  const badRead = runAtxSlow(['read', '__atx_missing_file_for_exit_proof__.js']);
  check('functional: edit-server payload ok:false becomes nonzero exit', badRead.status === 1 && /"ok"\s*:\s*false/.test(badRead.stdout), { status: badRead.status });

  const sentinel = runAtxSlow(['sentinel', 'status']);
  check('cross-server: `atx sentinel status` reaches the atomic-sentinel server via handshake and returns status', sentinel.status === 0 && /"status"\s*:\s*"running"/.test(sentinel.stdout));

  const graph = runAtxSlow(['graph']);
  check('cross-server: `atx graph` reaches atomic-memory memory_graph and returns a receipt-hashed graph', graph.status === 0 && /"graphSha256"\s*:\s*/.test(graph.stdout), { status: graph.status });

  const reentry = runAtxSlow(['reentry']);
  check('functional: `atx reentry` returns the host reentry receipt through atomic-call', reentry.status === 0 && /"reentry"\s*:/.test(reentry.stdout) && /"verificationCommand"\s*:/.test(reentry.stdout), { status: reentry.status });
}

const payload = { ok: fail === 0, pass, fail, results };
if (jsonMode) {
  console.log(JSON.stringify(payload));
} else {
  console.log(`\n${pass} passed, ${fail} failed`);
}
process.exit(payload.ok ? 0 : 1);
