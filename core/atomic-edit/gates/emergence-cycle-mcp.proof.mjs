#!/usr/bin/env node
/**
 * emergence-cycle-mcp.proof.mjs - proves the live Atomic emergence pulse is wired into MCP, CLI, build, and self-expansion.
 */
import * as childProcess from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const jsonMode = process.argv.includes('--json');
const sourceDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(sourceDir, '..', '..');
const results = [];

function record(name, ok, detail = {}) {
  results.push({ name, ok: Boolean(ok), detail });
}

function compact(value, bytes = 1600) {
  const text = typeof value === 'string' ? value : JSON.stringify(value);
  return text.length > bytes ? text.slice(0, bytes) + '...[truncated]' : text;
}

function singleTool(args, cwd = repoRoot) {
  const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'atomic-emergence-cycle-proof-tool-'));
  try {
    const child = childProcess.spawnSync(process.execPath, [path.join(sourceDir, 'dist', 'server.js')], {
      cwd,
      env: {
        ...process.env,
        ATOMIC_SINGLE_TOOL_CALL: '1',
        ATOMIC_SINGLE_TOOL_NAME: 'atomic_emergence_cycle',
        ATOMIC_SINGLE_TOOL_ARGS_JSON: JSON.stringify(args),
        ATOMIC_DISABLE_HOT_RELOAD: '1',
        CODEX_PROJECT_DIR: repoRoot,
        TMPDIR: tmpRoot,
        TMP: tmpRoot,
        TEMP: tmpRoot,
      },
      encoding: 'utf8',
      timeout: 180000,
      maxBuffer: 48 * 1024 * 1024,
    });
    let payload = null;
    try {
      payload = JSON.parse(child.stdout.trim() || '{}');
    } catch {
      payload = { parseError: compact(child.stdout || '') };
    }
    const content = Array.isArray(payload?.result?.content) ? payload.result.content : [];
    let machine = null;
    try {
      const text = content.length > 0 ? content[content.length - 1].text : '{}';
      machine = JSON.parse(text || '{}');
    } catch {
      machine = { parseError: content.length };
    }
    return { status: child.status, signal: child.signal, stderr: compact(child.stderr || ''), payloadOk: payload?.ok === true, machine };
  } finally {
    fs.rmSync(tmpRoot, { recursive: true, force: true });
  }
}

const serverSource = fs.readFileSync(path.join(sourceDir, 'server.ts'), 'utf8');
const toolSource = fs.readFileSync(path.join(sourceDir, 'server-tools-emergence-cycle.ts'), 'utf8');
const atxSource = fs.readFileSync(path.join(sourceDir, 'atx.mjs'), 'utf8');
const buildSource = fs.readFileSync(path.join(sourceDir, 'build.mjs'), 'utf8');
const selfSource = fs.readFileSync(path.join(sourceDir, 'server-tools-self.ts'), 'utf8');
const latticeSource = fs.readFileSync(path.join(sourceDir, 'gates', 'self-expansion-validator-lattice.proof.mjs'), 'utf8');
const emergenceImportPath = '.' + '/server-tools-' + 'emergence-cycle.js';

record('server imports and registers atomic_emergence_cycle',
  serverSource.includes("import { registerToolsEmergenceCycle } from '" + emergenceImportPath + "';") &&
    serverSource.includes('registerToolsEmergenceCycle(server);'));
record('tool exposes report and once modes and refuses promotion claims',
  toolSource.includes("'atomic_emergence_cycle'") &&
    toolSource.includes("mode === 'once'") &&
    toolSource.includes('continuous-emergence-loop.mjs') &&
    toolSource.includes('strongClaimAllowed') &&
    toolSource.includes('promotion remains atomic_expand_self'));
record('atx pulse routes through atomic_emergence_cycle',
  atxSource.includes('pulse:') && atxSource.includes("tool: 'atomic_emergence_cycle'"));
record('build compiles the emergence cycle tool and asserts the dist artifact',
  buildSource.includes("'server-tools-" + "emergence-cycle.ts'") &&
    buildSource.includes("'server-tools-" + "emergence-cycle.js'"));
record('self-expansion lattice makes the emergence cycle proof mandatory',
  selfSource.includes("{ phase: 'emergence-cycle', command: 'node gates/emergence-cycle-mcp.proof.mjs --json' }") &&
    latticeSource.includes("'node gates/emergence-cycle-mcp.proof.mjs --json'") &&
    latticeSource.includes("'emergence-cycle'"));

const build = childProcess.spawnSync(process.execPath, ['build.mjs'], {
  cwd: sourceDir,
  encoding: 'utf8',
  timeout: 180000,
  maxBuffer: 48 * 1024 * 1024,
});
record('build succeeds before MCP execution', build.status === 0, { status: build.status, stderr: compact(build.stderr || '') });

const reportCall = singleTool({ mode: 'report', repoRoot, timeoutMs: 60000 });
record('report mode exits cleanly and is read-only',
  reportCall.status === 0 && reportCall.payloadOk && reportCall.machine?.changed === false,
  { status: reportCall.status, stderr: reportCall.stderr, parseError: reportCall.machine?.parseError });
record('report mode returns the eight-organ cortex and honest decision',
  Array.isArray(reportCall.machine?.organs) && reportCall.machine.organs.length === 8 &&
    typeof reportCall.machine?.decision?.strongClaimAllowed === 'boolean' &&
    /^[a-f0-9]{64}$/.test(String(reportCall.machine?.receiptSha256 || '')),
  { organs: reportCall.machine?.organs?.map?.((organ) => organ.id), decision: reportCall.machine?.decision });

const proofRoot = fs.mkdtempSync(path.join(sourceDir, '.emergence-cycle-proof-'));
try {
  const onceCall = singleTool({ mode: 'once', repoRoot: proofRoot, timeoutMs: 180000 }, repoRoot);
  record('once mode runs the existing continuous emergence loop through MCP',
    onceCall.status === 0 && onceCall.payloadOk && onceCall.machine?.changed === true,
    { status: onceCall.status, stderr: onceCall.stderr, parseError: onceCall.machine?.parseError });
  const stepNames = onceCall.machine?.summary?.lastCycle?.stepNames ?? [];
  record('once mode verifies the resulting hash-chained feed and organ order',
    onceCall.machine?.summary?.feedChain?.ok === true &&
      ['../atomic-edit-evolution/corpus-accumulator', 'hypothesis-generator', 'autonomous-evolution', 'emergence-observatory'].every((step, index) => stepNames[index] === step),
    { feedChain: onceCall.machine?.summary?.feedChain, stepNames });
} finally {
  fs.rmSync(proofRoot, { recursive: true, force: true });
}

const ok = results.every((result) => result.ok);
if (jsonMode) {
  console.log(JSON.stringify({ ok, pass: results.filter((r) => r.ok).length, fail: results.filter((r) => !r.ok).length, results }, null, 2));
} else {
  for (const result of results) console.log(`${result.ok ? 'ok' : 'not ok'} - ${result.name}${result.ok ? '' : ' ' + compact(result.detail)}`);
  console.log(ok ? 'emergence-cycle-mcp proof OK' : 'emergence-cycle-mcp proof FAILED');
}
process.exit(ok ? 0 : 1);
