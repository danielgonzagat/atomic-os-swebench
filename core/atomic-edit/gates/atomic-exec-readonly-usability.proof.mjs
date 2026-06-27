#!/usr/bin/env node
import path from 'node:path';
import * as childProcess from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { installInheritedAtomicHostEnv } from './proof-host-env.mjs';

/**
 * atomic_exec read-only usability proof.
 *
 * The no-bypass shell operator must still be useful for mandatory read-side
 * repo inspection. In both direct sandbox mode and host/broker mode, read-only
 * commands should run with fileWrites=denied. Host/broker mode uses the broker's
 * explicit no-write envelope, so repo-root inspection does not depend on a
 * whole-monorepo byte-effect snapshot. Protected write attempts remain refused.
 */
const jsonMode = process.argv.includes('--json');
const sourceDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(sourceDir, '..', '..');
const hostVisibleRepoRoot = repoRoot;
let hostMode = false;
const readOnlyArgs = {};
const readOnlyCwd = hostVisibleRepoRoot;
const protectedReadCommand = "sed -n '1,1p' core/atomic-edit/package.json";
const TOOL_CALL_TIMEOUT_MS = 60000;

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

async function callAtomicExec(client, command, args = {}) {
  const compiledServer = path.join(sourceDir, 'dist', 'server.js');
  const result = childProcess.spawnSync(process.execPath, [compiledServer], {
    cwd: hostVisibleRepoRoot,
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
        cwd: readOnlyCwd,
        timeoutMs: 30000,
        ...args,
      }),
    },
  });
  if (result.error) throw new Error(`atomic_exec read-only proof call failed: ${result.error.message}`);
  const payload = JSON.parse(result.stdout || '{}');
  const content = Array.isArray(payload?.result?.content) ? payload.result.content : [];
  return parseToolResult({ content });
}

function serverTransport() {
  const inheritedHostEnv = installInheritedAtomicHostEnv(hostVisibleRepoRoot);
  hostMode = inheritedHostEnv.ATOMIC_HOST_SANDBOX === 'macos-sandbox-exec' && inheritedHostEnv.ATOMIC_HOST_ATOMIC_ONLY === '1';
  const compiledServer = path.join(sourceDir, 'dist', 'server.js');
  return new StdioClientTransport({
    command: process.execPath,
    args: [compiledServer],
    cwd: hostVisibleRepoRoot,
    stderr: 'pipe',
    env: inheritedHostEnv,
  });
}

function hostReadOnlyEffectOk(result) {
  return (
    result.atomicEnvelope?.sandbox?.active === true &&
    result.atomicEnvelope?.sandbox?.fileWrites === 'denied' &&
    result.atomicEnvelope?.effectProven === false &&
    result.effect === null
  );
}

function readOnlySandboxOk(result) {
  if (hostMode) return hostReadOnlyEffectOk(result);
  return result.atomicEnvelope?.sandbox?.fileWrites === 'denied';
}

async function main() {
  const results = [];
  const client = null;

  try {
    const protectedRead = await callAtomicExec(
      client,
      protectedReadCommand,
      { intent: 'proof read protected governance file without shell write', ...readOnlyArgs },
    );
    record(
      results,
      hostMode
        ? 'host/broker read-only sed may inspect protected governance file with no command write permission'
        : 'read-only sed may inspect protected governance file without being classified as shell write',
      protectedRead.ok === true &&
        protectedRead.commandClass === 'read-only' &&
        readOnlySandboxOk(protectedRead) &&
        String(protectedRead.stdout ?? '').length > 0,
      {
        ok: protectedRead.ok,
        commandClass: protectedRead.commandClass,
        cwd: protectedRead.cwd,
        sandbox: protectedRead.atomicEnvelope?.sandbox,
        effectProven: protectedRead.atomicEnvelope?.effectProven,
        effect: protectedRead.effect,
        stdoutBytes: String(protectedRead.stdout ?? '').length,
        error: protectedRead.error,
        stderr: protectedRead.stderr,
        hostMode,
      },
    );

    const protectedWrite = await callAtomicExec(
      client,
      "sed -i '' -e 's/__atomic_never__/__atomic_never__/g' core/atomic-edit/package.json",
      { cwd: readOnlyCwd, intent: 'proof protected governance sed write remains refused' },
    );
    record(
      results,
      'sed in-place write to protected governance file remains refused before spawn',
      protectedWrite.ok === false && /governance-protected|Protected files are owner-only/i.test(String(protectedWrite.error ?? '')),
      {
        ok: protectedWrite.ok,
        error: protectedWrite.error,
        stdoutBytes: String(protectedWrite.stdout ?? '').length,
        stderr: protectedWrite.stderr,
      },
    );

    const gitStatus = await callAtomicExec(
      client,
      'git status --short --branch',
      {
        intent: 'proof git read-only inspection works at repo root inside atomic sandbox',
        env: { GIT_OPTIONAL_LOCKS: '0' },
        ...readOnlyArgs,
      },
    );
    const gitText = String((gitStatus.stdout ?? '') + '\n' + (gitStatus.stderr ?? ''));
    record(
      results,
      hostMode
        ? 'host/broker repo-root read-only git status works with no command write permission despite /dev/null usage'
        : 'read-only git status works inside sandbox despite /dev/null usage',
      gitStatus.ok === true &&
        gitStatus.commandClass === 'read-only' &&
        readOnlySandboxOk(gitStatus) &&
        !/could not open '\/dev\/null'|Operation not permitted/i.test(gitText),
      {
        ok: gitStatus.ok,
        commandClass: gitStatus.commandClass,
        cwd: gitStatus.cwd,
        sandbox: gitStatus.atomicEnvelope?.sandbox,
        effectProven: gitStatus.atomicEnvelope?.effectProven,
        effect: gitStatus.effect,
        stdoutBytes: String(gitStatus.stdout ?? '').length,
        stderr: gitStatus.stderr,
        hostMode,
      },
    );
  } finally {}

  return { ok: results.every((entry) => entry.ok), results };
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
