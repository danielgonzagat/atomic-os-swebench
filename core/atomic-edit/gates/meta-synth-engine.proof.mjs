#!/usr/bin/env node
import * as childProcess from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const json = process.argv.includes('--json');
let failures = 0;
const details = [];

function check(name, condition, detail = '') {
  const ok = Boolean(condition);
  if (!ok) failures += 1;
  details.push({ name, ok, detail });
  if (!json) console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ` - ${detail}` : ''}`);
}

const dir = path.dirname(fileURLToPath(import.meta.url));
const atomicRoot = path.resolve(dir, '..');
const read = (rel) => fs.readFileSync(path.join(atomicRoot, rel), 'utf8');

const test = childProcess.spawnSync('npm', ['test', '--', 'engine-synthesis-kernel.test.ts'], {
  cwd: atomicRoot,
  encoding: 'utf8',
  timeout: 30_000,
});

const kernel = read('engine-synthesis-kernel.ts');
const cvc5 = read('engine-cvc5-sygus.ts');
const meta = read('engine-meta-synth.ts');
const server = read('server.ts');

check('focused kernel tests pass', test.status === 0, (test.stdout + test.stderr).slice(-500));
check('live kernel surface exists', /export function runSynthesisKernel/.test(kernel) && /export interface ProofReceipt/.test(kernel));
check('receipt verdict lattice exists in code', /HEURISTIC_UNPROVEN/.test(kernel) && /PROVEN/.test(kernel) && /ABSENT/.test(kernel));
check('CVC5 adapter emits explicit absence evidence', /detectCvc5/.test(cvc5) && /checked/.test(cvc5) && /ABSENT/.test(cvc5));
check('Z3 backend invokes the real coupling cover solver', /coupling_cover_z3\.py/.test(kernel) && /spawnSync/.test(kernel));
check('heuristic is not promotion eligible', /verdict === 'PROVEN' && receipt\.authority === 'formal'/.test(kernel));
check('meta synthesis returns proof limits', /Only verified formal PROVEN receipts/.test(meta));
check('MCP tool is registered', /registerToolsMetaSynth/.test(server) && /atomic_meta_synth/.test(read('server-tools-meta-synth.ts')));
check('no backend writes directly to engine files', !/writeFileSync|appendFileSync|atomicWrite/.test(kernel + cvc5 + meta));

if (json) {
  console.log(JSON.stringify({ ok: failures === 0, failures, details }, null, 2));
} else {
  console.log(failures === 0 ? 'OK - meta-synth-engine (0 failures)' : `FAIL - meta-synth-engine (${failures} failure(s))`);
}

process.exit(failures === 0 ? 0 : 1);
