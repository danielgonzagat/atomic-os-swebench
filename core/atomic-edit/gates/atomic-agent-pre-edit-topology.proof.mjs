#!/usr/bin/env node
/**
 * atomic-agent-pre-edit-topology.proof.mjs
 *
 * Proves the local Atomic Agent CLI carries the generalist lesson from
 * CODEX-VS-ATOMIC-L01-F: choose the minimal implementation topology before
 * the first edit, instead of writing duplicated logic and relying on a
 * post-green minimization repair.
 */
import * as fs from 'node:fs';
import * as path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const jsonMode = process.argv.includes('--json');
const sourceDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(sourceDir, '../..');
const agentPath = path.join(repoRoot, 'core/agent/atomic-full-ab/local-loop/local_atomic_agent.py');
const source = fs.readFileSync(agentPath, 'utf8');
const results = [];
function record(name, ok, detail = {}) { results.push({ name, ok: Boolean(ok), detail }); }

record('agent has pre-edit topology state',
  source.includes('pre_edit_topology_prompted = False') && source.includes('pre_edit_topology_active = False'),
  { prompted: source.includes('pre_edit_topology_prompted = False'), active: source.includes('pre_edit_topology_active = False') });
record('topology prompt triggers after body-level reads (not navigation) and before first edit',
  source.includes('metrics["edits_applied"] == 0 and metrics["body_context_reads"] > 0 and not pre_edit_topology_prompted') &&
  source.includes('Before the first edit, choose the smallest implementation topology'),
  { guard: source.includes('metrics["edits_applied"] == 0 and metrics["body_context_reads"] > 0 and not pre_edit_topology_prompted') });
record('body-context reads are counted only for code-body reads (atomic_read / atomic_read_many), not navigation (L01-H)',
  source.includes('"body_context_reads": 0,') &&
  source.includes('if fn in ("atomic_read", "atomic_read_many"):') &&
  source.includes('metrics["body_context_reads"] += 1'),
  { init: source.includes('"body_context_reads": 0,'), counted: source.includes('metrics["body_context_reads"] += 1') });
record('topology prompt requires canonical implementation and delegating wrappers',
  source.includes('name the canonical implementation location') &&
  source.includes('delegating wrappers') &&
  source.includes('preserves public exports') &&
  source.includes('minimizing changed bytes') &&
  source.includes('prefer one canonical implementation plus wrappers before writing duplicated logic'),
  {
    canonical: source.includes('name the canonical implementation location'),
    wrappers: source.includes('delegating wrappers'),
    exports: source.includes('preserves public exports'),
    bytes: source.includes('minimizing changed bytes'),
  });
record('tool calls are refused while pre-edit topology decision is active',
  source.includes('PRE-EDIT TOPOLOGY DECISION REQUIRED') &&
  source.includes('REFUSED (pre-edit topology active)') &&
  source.includes('reply in text only, no tool call'),
  { refusal: source.includes('PRE-EDIT TOPOLOGY DECISION REQUIRED') });
record('text topology decision is recorded before implementation resumes',
  source.includes('PRE-EDIT-TOPOLOGY decision:') &&
  source.includes('Now implement that topology with the smallest faithful atomic edit(s), then run_tests.'),
  { decision: source.includes('PRE-EDIT-TOPOLOGY decision:') });
const py = spawnSync('python3', ['-m', 'py_compile', agentPath], { cwd: repoRoot, encoding: 'utf8', timeout: 20000, maxBuffer: 1024 * 1024 });
record('local_atomic_agent.py remains valid Python after pre-edit topology update', py.status === 0, { status: py.status, signal: py.signal, stderr: py.stderr });
const ok = results.every((entry) => entry.ok);
if (jsonMode) console.log(JSON.stringify({ ok, results }, null, 2));
else for (const entry of results) console.log((entry.ok ? 'PASS' : 'FAIL') + ' ' + entry.name);
process.exit(ok ? 0 : 1);
