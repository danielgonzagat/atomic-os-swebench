#!/usr/bin/env node
/**
 * Regression proof for the supervisor LKG recovery branch.
 *
 * A live session can legitimately be served from dist-lkg after a stale host
 * broker or broken impl path. Once that session is initialized, killing or
 * crashing the LKG child must restart LKG, not fall directly into rescue. Rapid
 * repeated failures still escalate through nextLadderStage() to rescue.
 */
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const jsonMode = process.argv.includes('--json');
const sourceDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(sourceDir, '..', '..');
const supervisor = fs.readFileSync(path.join(repoRoot, 'core/atomic-edit/launcher-supervisor.mjs'), 'utf8');
const results = [];

function record(name, ok, detail = {}) {
  results.push({ name, ok: Boolean(ok), detail });
  if (!jsonMode) process.stdout.write((ok ? 'PASS ' : 'FAIL ') + name + '\n');
}

function extractStage2Expression(source) {
  const marker = 'const stage2 = ';
  const start = source.indexOf(marker);
  const end = source.indexOf('\n  if (stage2 ===', start);
  if (start < 0 || end < 0) return null;
  return source.slice(start + marker.length, end).trim().replace(/;$/, '');
}

function nextLadderStage(prev) {
  if (prev === 'impl') return 'impl-restored';
  if (prev === 'impl-restored') return 'lkg';
  return 'rescue';
}

function selectStage(expr, initAnswered, stage, burst) {
  const fn = new Function('initAnswered', 'stage', 'firstFailureBurst', 'nextLadderStage', 'return (' + expr + ');');
  return fn(initAnswered, stage, () => burst, nextLadderStage);
}

const expr = extractStage2Expression(supervisor);
record('supervisor exposes a stage2 recovery selector', typeof expr === 'string' && expr.length > 0, { expr });
if (expr) {
  record('post-initialize lkg child exit respawns lkg instead of rescue', selectStage(expr, true, 'lkg', false) === 'lkg', { selected: selectStage(expr, true, 'lkg', false) });
  record('post-initialize normal child exit still restarts at impl', selectStage(expr, true, 'impl', false) === 'impl', { selected: selectStage(expr, true, 'impl', false) });
  record('rapid lkg failure burst still escalates to rescue', selectStage(expr, true, 'lkg', true) === 'rescue', { selected: selectStage(expr, true, 'lkg', true) });
  record('pre-initialize lkg boot failure still enters rescue', selectStage(expr, false, 'lkg', false) === 'rescue', { selected: selectStage(expr, false, 'lkg', false) });
}

const ok = results.every((entry) => entry.ok);
if (jsonMode) process.stdout.write(JSON.stringify({ ok, results }) + '\n');
process.exit(ok ? 0 : 1);
