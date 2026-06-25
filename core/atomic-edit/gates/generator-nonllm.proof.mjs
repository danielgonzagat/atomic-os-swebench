// generator-nonllm.proof.mjs — Adversarial proof gate for the non-LLM generator (Fase 2).
// PROVES:
//   (1) generateProposalsWithoutLlm queries effect-matched accept lessons;
//   (2) perfect match logic generates exact replay proposals;
//   (3) mutated matching logic adapts timeout values combinatorially to target files;
//   (4) returns zero proposals when no informative lessons match the target effect.

import { generateProposalsWithoutLlm } from '../dist/server-helpers-generator-nonllm.js';
import { recordLesson } from '../dist/server-helpers-lesson-ledger.js';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const json = process.argv.includes('--json');
let failures = 0;
function check(n, c) { const ok = !!c; if (!ok) failures += 1; if (!json) console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${n}`); }

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'generator-nonllm-proof-'));

// Criar arquivos alvo simulados no diretório temporário
fs.mkdirSync(path.join(root, 'src'), { recursive: true });
const targetFile1 = 'src/test-config.ts';
const targetFile2 = 'src/app-timeout.ts';

fs.writeFileSync(path.join(root, targetFile1), 'export const LIMIT = 100;\n');
fs.writeFileSync(path.join(root, targetFile2), 'const config = { timeoutMs: 5000 };\n');

// 1. Simular lição de replay exato
const op1 = { file: targetFile1, op: 'replace_text', oldText: 'export const LIMIT = 100;\n', newText: 'export const LIMIT = 500;\n' };
const eff1 = { gatesFlipped: ['node gates/limit-test.proof.mjs --json:RED->GREEN'], veredictDelta: 'RED->GREEN' };
recordLesson(root, {
  effect: eff1,
  operator: op1,
  decision: 'accept',
  context: { intent: 'raise limit' }
});

// 2. Simular lição de timeout mutável
const op2 = { file: targetFile2, op: 'replace_text', oldText: 'const config = { timeoutMs: 3000 };\n', newText: 'const config = { timeoutMs: 15000 };\n' };
const eff2 = { gatesFlipped: ['node gates/timeout-test.proof.mjs --json:RED->GREEN'], veredictDelta: 'RED->GREEN' };
recordLesson(root, {
  effect: eff2,
  operator: op2,
  decision: 'accept',
  context: { intent: 'increase timeout' }
});

// Teste 1: Replay exato
const prop1 = generateProposalsWithoutLlm(root, 'node gates/limit-test.proof.mjs --json');
check('proposals generated for limit-test', prop1.length === 1);
check('exact replay matched correctly', prop1[0] && prop1[0].newText === 'export const LIMIT = 500;\n');

// Teste 2: Mutação combinatória de timeout adaptada (timeout original na lição era 3000, no arquivo atual é 5000)
const prop2 = generateProposalsWithoutLlm(root, 'node gates/timeout-test.proof.mjs --json');
check('proposals generated for timeout-test', prop2.length === 1);
check('adapted timeout to target file correctly', prop2[0] && prop2[0].oldText === 'const config = { timeoutMs: 5000 };\n' && prop2[0].newText === 'const config = { timeoutMs: 15000 };\n');

// Teste 3: Sem lições informativas
const prop3 = generateProposalsWithoutLlm(root, 'node gates/nonexistent-test.proof.mjs --json');
check('no proposals generated for unmatched gate', prop3.length === 0);

// Limpeza
fs.rmSync(root, { recursive: true, force: true });

if (json) {
  console.log(JSON.stringify({ ok: failures === 0, failures, proposalsGenerated: prop1.length + prop2.length, gate: 'generator-nonllm' }));
} else {
  console.log(failures === 0 ? `\nOK — generator-nonllm proof (0 failures)` : `\nFAIL — generator-nonllm proof (${failures} failure(s))`);
}

process.exit(failures === 0 ? 0 : 1);
