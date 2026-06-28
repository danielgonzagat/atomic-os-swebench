#!/usr/bin/env node
/**
 * capability-genome-registry.proof.mjs - proves Atomic exposes a receipt-linked capability genome.
 */
import * as childProcess from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const jsonMode = process.argv.includes('--json');
const sourceDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(sourceDir, '../../..');
const results = [];

function record(name, ok, detail = {}) {
  results.push({ name, ok: Boolean(ok), detail });
}

function compact(value, bytes = 1200) {
  const text = typeof value === 'string' ? value : JSON.stringify(value);
  return text.length > bytes ? text.slice(0, bytes) + '...[truncated]' : text;
}

function loadGenomeModule() {
  const helperPath = path.join(sourceDir, 'dist', 'server-helpers-capability-genome.js');
  if (!fs.existsSync(helperPath)) throw new Error('compiled helper missing; run node build.mjs first');
  return import(helperPath);
}

function singleTool(args) {
  const proofTmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'atomic-capability-genome-proof-'));
  try {
    const child = childProcess.spawnSync(process.execPath, [path.join(sourceDir, 'dist', 'server.js')], {
      cwd: repoRoot,
      env: {
        ...process.env,
        ATOMIC_SINGLE_TOOL_CALL: '1',
        ATOMIC_SINGLE_TOOL_NAME: 'atomic_capability_genome',
        ATOMIC_SINGLE_TOOL_ARGS_JSON: JSON.stringify(args),
        ATOMIC_DISABLE_HOT_RELOAD: '1',
        CODEX_PROJECT_DIR: repoRoot,
        TMPDIR: proofTmpRoot,
        TMP: proofTmpRoot,
        TEMP: proofTmpRoot,
      },
      encoding: 'utf8',
      maxBuffer: 24 * 1024 * 1024,
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
    fs.rmSync(proofTmpRoot, { recursive: true, force: true });
  }
}

const module = await loadGenomeModule();
const registry = module.buildCapabilityGenomeRegistry(sourceDir);
const verification = module.verifyCapabilityGenomeRegistry(registry);

record('registry verifies', verification.ok, verification);
record('registry has capabilities', Array.isArray(registry.capabilities) && registry.capabilities.length > 0, { count: registry.capabilities?.length });
record('source digest is sha256', /^[a-f0-9]{64}$/.test(registry.sourceDigest), { sourceDigest: registry.sourceDigest });

const names = new Set(registry.capabilities.map((capability) => capability.toolName));
for (const required of ['atomic_expand_self', 'atomic_self_evolution', 'atomic_capability_genome']) {
  record(`required capability ${required}`, names.has(required));
}
record('memory organ present', registry.capabilities.some((capability) => capability.domain === 'memory'));
record('immune organ present', registry.capabilities.some((capability) => capability.domain === 'immune'));
record('discovery organ present', registry.capabilities.some((capability) => capability.domain === 'discovery'));

const promotedWithoutReceipt = registry.capabilities.filter((capability) => capability.status === 'promoted' && !capability.evidenceReceipts.some((receipt) => receipt.kind.includes('promotion') && typeof receipt.sha256 === 'string'));
record('no promoted capability without receipt', promotedWithoutReceipt.length === 0, { promotedWithoutReceipt });

const selfEvolution = registry.capabilities.find((capability) => capability.toolName === 'atomic_self_evolution');
record('self-evolution has archive evidence', Boolean(selfEvolution?.evidenceReceipts.some((receipt) => receipt.source === 'self-evolution-archive.jsonl')), { evidenceReceipts: selfEvolution?.evidenceReceipts });
record('self-evolution has required gates', Number(registry.evidence.selfEvolutionArchive.requiredGateCount) > 0, registry.evidence.selfEvolutionArchive);

const second = module.buildCapabilityGenomeRegistry(sourceDir);
record('source digest deterministic', second.sourceDigest === registry.sourceDigest, { first: registry.sourceDigest, second: second.sourceDigest });

const serverSource = fs.readFileSync(path.join(sourceDir, 'server.ts'), 'utf8');
record('server registers capability genome tool', serverSource.includes('registerToolsCapabilityGenome(server);'));

const mcpCall = singleTool({ toolName: 'atomic_capability_genome' });
const mcpBody = mcpCall.machine?.registry ?? null;
record('mcp tool call exits cleanly', mcpCall.status === 0 && mcpCall.payloadOk, { status: mcpCall.status, signal: mcpCall.signal, stderr: mcpCall.stderr });
record('mcp tool returns filtered capability', Array.isArray(mcpBody?.capabilities) && mcpBody.capabilities.some((capability) => capability.toolName === 'atomic_capability_genome'), { filters: mcpCall.machine?.filters, parseError: mcpCall.machine?.parseError });
record('mcp tool returns verification ok', mcpCall.machine?.verification?.ok === true, mcpCall.machine?.verification ?? {});

const ok = results.every((result) => result.ok);
if (jsonMode) {
  console.log(JSON.stringify({ ok, pass: results.filter((r) => r.ok).length, fail: results.filter((r) => !r.ok).length, results }, null, 2));
} else {
  for (const result of results) console.log(`${result.ok ? 'ok' : 'not ok'} - ${result.name}${result.ok ? '' : ' ' + compact(result.detail)}`);
  console.log(ok ? 'capability-genome-registry proof OK' : 'capability-genome-registry proof FAILED');
}
process.exit(ok ? 0 : 1);