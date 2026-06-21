#!/usr/bin/env node
/**
 * atomic-agent-lean-surface.proof.mjs
 *
 * Proves the local Atomic Agent CLI prompt carries the generalist lesson from
 * A/B loss class CODEX-VS-ATOMIC-L01-A: solve with the smallest faithful
 * behavioral delta and avoid duplicated state machines/parsers when a canonical
 * helper plus wrappers preserves public API with less surface.
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

function record(name, ok, detail = {}) {
  results.push({ name, ok: Boolean(ok), detail });
}

const surveyStart = source.indexOf('    survey = (');
const leanStart = source.indexOf('    lean = (');
const noGateSystem = source.indexOf('if NO_GATE:');
const withGateSystem = source.indexOf('    else:', noGateSystem);

record('agent defines an explicit lean-surface instruction block', leanStart > 0, { leanStart });
record(
  'lean instruction requires smallest correct behavioral delta',
  source.includes('smallest correct behavioral delta') && source.includes('preserve existing exports'),
  { hasSmallestDelta: source.includes('smallest correct behavioral delta'), hasPreserveExports: source.includes('preserve existing exports') },
);
record(
  'lean instruction prefers canonical implementation over duplicated parsers/state machines',
  source.includes('one canonical helper') && source.includes('wrappers delegate') && source.includes('duplicating state machines or parsers'),
  { hasCanonicalHelper: source.includes('one canonical helper'), hasWrappersDelegate: source.includes('wrappers delegate'), hasNoDuplication: source.includes('duplicating state machines or parsers') },
);
record(
  'both no-gate and feedback agent prompts include the lean instruction',
  source.includes('"ONLY atomic tools. " + survey + lean +') && source.includes('"ONLY atomic tools, plus run_tests to verify. " + survey + lean +'),
  { noGatePrompt: source.includes('"ONLY atomic tools. " + survey + lean +'), feedbackPrompt: source.includes('"ONLY atomic tools, plus run_tests to verify. " + survey + lean +') },
);
record(
  'lean policy is injected after read-efficiency guidance and before task execution guidance',
  surveyStart >= 0 && leanStart > surveyStart && leanStart < noGateSystem && noGateSystem < withGateSystem,
  { surveyStart, leanStart, noGateSystem, withGateSystem },
);
const py = spawnSync('python3', ['-m', 'py_compile', agentPath], { cwd: repoRoot, encoding: 'utf8', timeout: 20000, maxBuffer: 1024 * 1024 });
record('local_atomic_agent.py remains valid Python after prompt update', py.status === 0, { status: py.status, signal: py.signal, stderr: py.stderr });

const ok = results.every((entry) => entry.ok);
if (jsonMode) console.log(JSON.stringify({ ok, results }, null, 2));
else for (const entry of results) console.log((entry.ok ? 'PASS' : 'FAIL') + ' ' + entry.name);
process.exit(ok ? 0 : 1);
