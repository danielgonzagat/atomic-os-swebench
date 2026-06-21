#!/usr/bin/env node
/**
 * atomic-agent-text-only-topology.proof.mjs
 *
 * Proves CODEX-VS-ATOMIC-L01-G: text-only agent harness phases must withhold
 * tool schemas instead of exposing tools and relying on post-hoc refusals.
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

const conditionalTools = `if tools:
        payload["tools"] = tools`;
record('DeepSeek request omits tools when a text-only turn offers no schema',
  source.includes('payload = {"model": MODEL, "messages": messages,') &&
  source.includes(conditionalTools) &&
  !source.includes('"tools": tools,\n                       "temperature"'),
  { hasConditionalTools: source.includes(conditionalTools) });

const topologyTextOnly = `if pre_edit_topology_active:
            step_tools = []`;
const textOnlyIndex = source.indexOf(topologyTextOnly);
const callIndex = source.indexOf('msg, usage = deepseek(messages, step_tools)');
record('pre-edit topology decision withholds all tools before the model call',
  textOnlyIndex !== -1 && callIndex !== -1 && textOnlyIndex < callIndex &&
  source.includes('PRE-EDIT-TOPOLOGY tools withheld (text-only)'),
  { textOnlyIndex, callIndex });

record('defensive refusal remains for impossible or historical tool calls',
  source.includes('PRE-EDIT TOPOLOGY DECISION REQUIRED') &&
  source.includes('REFUSED (pre-edit topology active)'),
  { refusal: source.includes('PRE-EDIT TOPOLOGY DECISION REQUIRED') });

record('text topology decision is still recorded before implementation resumes',
  source.includes('PRE-EDIT-TOPOLOGY decision:') &&
  source.includes('Now implement that topology with the smallest faithful atomic edit(s), then run_tests.'),
  { decision: source.includes('PRE-EDIT-TOPOLOGY decision:') });

const py = spawnSync('python3', ['-m', 'py_compile', agentPath], { cwd: repoRoot, encoding: 'utf8', timeout: 20000, maxBuffer: 1024 * 1024 });
record('local_atomic_agent.py remains valid Python after text-only topology update', py.status === 0, { status: py.status, signal: py.signal, stderr: py.stderr });

const ok = results.every((entry) => entry.ok);
if (jsonMode) console.log(JSON.stringify({ ok, results }, null, 2));
else for (const entry of results) console.log((entry.ok ? 'PASS' : 'FAIL') + ' ' + entry.name);
process.exit(ok ? 0 : 1);
