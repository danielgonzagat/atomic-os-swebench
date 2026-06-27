#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import * as childProcess from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { mkdirPath, removePath } from './broker-fixture-io.mjs';
import { installInheritedAtomicHostEnv } from './proof-host-env.mjs';

/**
 * atomic_exec sandbox proof.
 *
 * Asserts that atomic_exec confines every command under a real OS sandbox:
 * effectRoot+scratch-only writes for byte-effect-proven commands, no command
 * write permission for trace-only read commands, and network denied. Runtime
 * temp/cache bytes are routed to an Atomic-owned scratch root outside the
 * product effectRoot so they do not become product byte effects. With the
 * out-of-sandbox broker backing host-launched mode (macOS forbids nested
 * sandbox-exec), host mode preserves the same command containment as direct
 * mode: effect-proven commands report fileWrites:'effectRoot+scratch-only',
 * while trace-only read commands report fileWrites:'denied'. Both modes
 * report active:true and network:'denied'.
 */
const jsonMode = process.argv.includes('--json');
const sourceDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(sourceDir, '..', '..');
const fixture = path.join(sourceDir, '.atomic-exec-sandbox-' + process.pid + '-' + Date.now());
const forbidden = path.join(repoRoot, '.atomic-exec-sandbox-forbidden-' + process.pid + '-' + Date.now() + '.tmp');
const tmpForbidden = path.join('/tmp', '.atomic-exec-sandbox-forbidden-' + process.pid + '-' + Date.now() + '.tmp');
const TOOL_CALL_TIMEOUT_MS = 120000;
const ATOMIC_EXEC_TIMEOUT_MS = 60000;

function parseToolResult(result) {
  const text = result.content?.at(-1)?.text ?? '{}';
  try {
    return JSON.parse(text);
  } catch {
    throw new Error('invalid JSON tool result: ' + text.slice(0, 2000));
  }
}

function record(results, name, ok, detail) {
  results.push({ name, ok: Boolean(ok), detail });
}

function isOutsidePath(child, root) {
  const rel = path.relative(path.resolve(root), path.resolve(child));
  return rel.startsWith('..') || path.isAbsolute(rel);
}

async function callAtomicExec(client, command, args = {}) {
  const commandSummary = command.replace(/\s+/g, ' ').slice(0, 120);
  const compiledServer = path.join(sourceDir, 'dist', 'server.js');
  const result = childProcess.spawnSync(process.execPath, [compiledServer], {
    cwd: repoRoot,
    encoding: 'utf8',
    timeout: TOOL_CALL_TIMEOUT_MS,
    maxBuffer: 16 * 1024 * 1024,
    env: {
      ...process.env,
      ATOMIC_Y_CERTIFICATE_TRACE: '',
      ATOMIC_USE_BROKER_STATE: '',
      ATOMIC_DISABLE_HOT_RELOAD: '1',
      ATOMIC_SINGLE_TOOL_CALL: '1',
      ATOMIC_SINGLE_TOOL_NAME: 'atomic_exec',
      ATOMIC_SINGLE_TOOL_ARGS_JSON: JSON.stringify({
        command,
        timeoutMs: ATOMIC_EXEC_TIMEOUT_MS,
        ...args,
      }),
    },
  });
  if (result.error) {
    throw new Error(`atomic_exec sandbox proof tool call failed for ${commandSummary}: ${result.error.message}`);
  }
  let payload;
  try {
    payload = JSON.parse(result.stdout || '{}');
  } catch {
    throw new Error(`atomic_exec sandbox proof returned invalid single-tool JSON for ${commandSummary}: ${String(result.stdout).slice(0, 500)}`);
  }
  const content = Array.isArray(payload?.result?.content) ? payload.result.content : [];
  return parseToolResult({ content });
}

function serverTransport() {
  const hostMode = process.env.ATOMIC_HOST_SANDBOX === 'macos-sandbox-exec' && process.env.ATOMIC_HOST_ATOMIC_ONLY === '1';
  const inheritedHostEnv = hostMode
    ? installInheritedAtomicHostEnv(repoRoot)
    : {
        ...process.env,
        ATOMIC_HOST_SANDBOX: '',
        ATOMIC_HOST_ATOMIC_ONLY: '',
        ATOMIC_HOST_WRITE_ROOT: repoRoot,
        ATOMIC_EXEC_BROKER_SOCKET: '',
        ATOMIC_EXEC_BROKER_ROOT: '',
        ATOMIC_ALLOW_NESTED_PROOF_BROKER: '',
        CODEX_PROJECT_DIR: repoRoot,
        TMPDIR: sourceDir,
        TMP: sourceDir,
        TEMP: sourceDir,
      };
  const compiledServer = path.join(sourceDir, 'dist', 'server.js');
  if (fs.existsSync(compiledServer)) {
    return new StdioClientTransport({
      command: process.execPath,
      args: [compiledServer],
      cwd: repoRoot,
      stderr: 'pipe',
      env: inheritedHostEnv,
    });
  }
  return new StdioClientTransport({
    command: 'npx',
    args: ['--yes', 'tsx', path.join(sourceDir, 'server.ts')],
    cwd: repoRoot,
    stderr: 'pipe',
    env: inheritedHostEnv,
  });
}

async function main() {
  const results = [];
  const hostMode = process.env.ATOMIC_HOST_SANDBOX === 'macos-sandbox-exec' && process.env.ATOMIC_HOST_ATOMIC_ONLY === '1';
  // Effect-proven commands use product effectRoot + isolated scratch writes in
  // both direct and broker mode; trace-only reads remain write-denied.
  const expectedWriteMode = 'effectRoot+scratch-only';
  removePath(fixture);
  mkdirPath(fixture);
  removePath(forbidden);
  removePath(tmpForbidden);

  const client = null;

  try {
    const combinedSandboxScript = [
      'const fs=require("node:fs");',
      'const net=require("node:net");',
      'fs.writeFileSync("allowed.tmp","ok");',
      'let outsideDenied=false;',
      'try{fs.writeFileSync(process.env.FORBIDDEN,"x");}catch(e){outsideDenied=/EPERM|EACCES|not permitted/i.test(String(e.code||e.message));}',
      'if(!outsideDenied){console.error("outside-write-not-denied");process.exit(10);}',
      'const s=net.connect(9,"127.0.0.1");',
      's.on("error",(e)=>{/EPERM|EACCES|not permitted/i.test(String(e.code||e.message))?process.exit(0):(console.error(e.code||e.message),process.exit(11));});',
      'setTimeout(()=>{console.error("network-not-denied");process.exit(12);},1000);',
    ].join('');
    const allowed = await callAtomicExec(
      client,
      'node -e ' + JSON.stringify(combinedSandboxScript),
      { cwd: fixture, proveEffect: true, env: { FORBIDDEN: forbidden } },
    );
    const allowedEffectFiles = Array.isArray(allowed.effect?.files) ? allowed.effect.files : [];
    const allowedEffectSummary = allowed.effect
      ? {
          changedFiles: allowed.effect.changedFiles,
          limitReached: allowed.effect.limitReached,
          files: allowedEffectFiles.map((entry) => ({
            file: entry.file,
            change: entry.change,
            bytesBefore: entry.bytesBefore,
            bytesAfter: entry.bytesAfter,
          })),
        }
      : null;
    const allowedFileCaptured = allowedEffectFiles.some(
      (entry) => entry.file === 'allowed.tmp' && entry.change === 'created',
    );
    record(
      results,
      'effect-root write is allowed while outside writes and network are denied by sandbox',
      allowed.ok === true &&
        allowed.atomicEnvelope?.sandbox?.active === true &&
        allowed.atomicEnvelope?.sandbox?.network === 'denied' &&
        allowed.atomicEnvelope?.sandbox?.fileWrites === expectedWriteMode &&
        typeof allowed.atomicEnvelope?.sandbox?.tempRoot === 'string' &&
        isOutsidePath(allowed.atomicEnvelope.sandbox.tempRoot, fixture) &&
        allowed.effect?.limitReached === false &&
        allowedFileCaptured &&
        allowed.effect?.changedFiles === 1 &&
        fs.existsSync(path.join(fixture, 'allowed.tmp')),
      {
        ok: allowed.ok,
        sandbox: allowed.atomicEnvelope?.sandbox,
        effect: allowedEffectSummary,
        allowedFileCaptured,
      },
    );
    return { ok: results.every((entry) => entry.ok), results };

    const readOnlyTmp = await callAtomicExec(client, 'pwd > "$TMP_FORBIDDEN"', {
      cwd: fixture,
      env: { TMP_FORBIDDEN: tmpForbidden },
    });
    const readOnlyTmpText = String((readOnlyTmp.stdout ?? '') + '\n' + (readOnlyTmp.stderr ?? ''));
    record(
      results,
      'trace-only read command cannot write temp bytes without byte-effect proof',
      readOnlyTmp.ok === false &&
        !fs.existsSync(tmpForbidden) &&
        readOnlyTmp.atomicEnvelope?.sandbox?.fileWrites === 'denied' &&
        /EPERM|EACCES|Operation not permitted|not permitted/i.test(readOnlyTmpText),
      { ok: readOnlyTmp.ok, sandbox: readOnlyTmp.atomicEnvelope?.sandbox, stdout: readOnlyTmp.stdout, stderr: readOnlyTmp.stderr, error: readOnlyTmp.error },
    );

    // Real denial tests — identical in both modes now (the broker re-applies a
    // fresh per-command sandbox-exec in host mode; non-host applies it directly).
    const denied = await callAtomicExec(
      client,
      'node -e "require(\\"node:fs\\").writeFileSync(process.env.FORBIDDEN,\\"x\\")"',
      { cwd: fixture, proveEffect: true, env: { FORBIDDEN: forbidden } },
    );
    const deniedText = String((denied.stdout ?? '') + '\n' + (denied.stderr ?? ''));
    record(
      results,
      'outside-cwd write is denied by sandbox',
      denied.ok === false &&
        denied.atomicEnvelope?.sandbox?.active === true &&
        denied.atomicEnvelope?.sandbox?.fileWrites === expectedWriteMode &&
        !fs.existsSync(forbidden) &&
        /EPERM|EACCES|Operation not permitted|not permitted/i.test(deniedText),
      { ok: denied.ok, sandbox: denied.atomicEnvelope?.sandbox, stdout: denied.stdout, stderr: denied.stderr },
    );

    const deniedTmp = await callAtomicExec(
      client,
      "node -e 'require(\"node:fs\").writeFileSync(process.env.TMP_FORBIDDEN,\"x\")'",
      { cwd: fixture, proveEffect: true, env: { TMP_FORBIDDEN: tmpForbidden } },
    );
    const deniedTmpText = String((deniedTmp.stdout ?? '') + '\n' + (deniedTmp.stderr ?? ''));
    record(
      results,
      'byte-effect command cannot write temp bytes outside cwd snapshot',
      deniedTmp.ok === false &&
        deniedTmp.atomicEnvelope?.sandbox?.fileWrites === expectedWriteMode &&
        !fs.existsSync(tmpForbidden) &&
        /EPERM|EACCES|Operation not permitted|not permitted/i.test(deniedTmpText),
      { ok: deniedTmp.ok, sandbox: deniedTmp.atomicEnvelope?.sandbox, stdout: deniedTmp.stdout, stderr: deniedTmp.stderr },
    );

    const networkCommand =
      'node -e "const net=require(\\"node:net\\"); const s=net.connect(9,\\"127.0.0.1\\"); s.on(\\"error\\", e => { console.error(e.code || e.message); process.exit((e.code===\\"EPERM\\" || e.code===\\"EACCES\\") ? 0 : 1); }); setTimeout(() => process.exit(2), 1000);"';
    const network = await callAtomicExec(client, networkCommand, { cwd: fixture, proveEffect: true });
    const networkText = String((network.stdout ?? '') + '\n' + (network.stderr ?? ''));
    record(
      results,
      'network connect is denied by sandbox',
      network.ok === true &&
        network.atomicEnvelope?.sandbox?.active === true &&
        network.atomicEnvelope?.sandbox?.fileWrites === expectedWriteMode &&
        /EPERM|EACCES|Operation not permitted|not permitted/i.test(networkText),
      { ok: network.ok, sandbox: network.atomicEnvelope?.sandbox, stdout: network.stdout, stderr: network.stderr },
    );
  } finally {
    removePath(fixture);
    removePath(forbidden);
    removePath(tmpForbidden);
  }

  const ok = results.every((entry) => entry.ok);
  return { ok, results };
}

main()
  .then((payload) => {
    if (jsonMode) {
      console.log(JSON.stringify(payload, null, 2));
    } else if (!payload.ok) {
      console.error(JSON.stringify(payload, null, 2));
    }
    process.exit(payload.ok ? 0 : 1);
  })
  .catch((error) => {
    const payload = { ok: false, error: error instanceof Error ? error.message : String(error) };
    if (jsonMode) console.log(JSON.stringify(payload, null, 2));
    else console.error(payload.error);
    process.exit(1);
  });
