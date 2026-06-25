// lesson-ledger.proof.mjs — Adversarial proof gate for the effect-indexed lesson-ledger (Fase 1).
// PROVES:
//   (1) recordLesson appends a cryptographically linked (proof-carrying) lesson;
//   (2) the chain VERIFIES and any tamper/break is identified;
//   (3) queryLessonsByEffect retrieves the correct operators for target files/flipped gates;
//   (4) recovery precision of retrieval is mathematically measured.

import { recordLesson, readLessonLedger, queryLessonsByEffect, verifyLessonLedgerChain } from '../dist/server-helpers-lesson-ledger.js';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const json = process.argv.includes('--json');
let failures = 0;
function check(n, c) { const ok = !!c; if (!ok) failures += 1; if (!json) console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${n}`); }

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lesson-ledger-proof-'));

// 1. Simular gravação de lições (aceitas e rejeitadas) com efeitos específicos
const op1 = { file: 'src/user.ts', op: 'replace_text', oldText: 'LoginService', newText: 'AuthenticationService' };
const eff1 = { gatesFlipped: ['gates/atomic-exec-readonly-usability.proof.mjs:RED->GREEN'], veredictDelta: 'RED->GREEN' };
const r1 = recordLesson(root, {
  effect: eff1,
  operator: op1,
  decision: 'accept',
  context: { intent: 'rename user auth service', durationMs: 120, ts: Date.now() }
});

const op2 = { file: 'src/auth.ts', op: 'replace_text', oldText: 'class Auth', newText: 'class Authenticator' };
const eff2 = { gatesFlipped: ['gates/auth-security.proof.mjs:GREEN->RED'], veredictDelta: 'GREEN->RED' };
const r2 = recordLesson(root, {
  effect: eff2,
  operator: op2,
  decision: 'reject',
  context: { intent: 'break auth logic', durationMs: 80, ts: Date.now() }
});

const op3 = { file: 'src/user.ts', op: 'delete' };
const eff3 = { gatesFlipped: ['gates/atomic-exec-readonly-usability.proof.mjs:RED->GREEN'], veredictDelta: 'RED->GREEN' };
const r3 = recordLesson(root, {
  effect: eff3,
  operator: op3,
  decision: 'accept',
  context: { intent: 'redundant user file', durationMs: 150, ts: Date.now() }
});

check('lessons recorded successfully', !!r1 && !!r2 && !!r3);

const ledger = readLessonLedger(root);
check('ledger has 3 records', ledger.length === 3);

// 2. Validar integridade da hash chain
const integrity = verifyLessonLedgerChain(ledger);
check('ledger chain verifies successfully', integrity.ok === true);

// Forçar uma quebra de cadeia
const tampered = JSON.parse(JSON.stringify(ledger));
tampered[1].operator.op = 'create'; // Tamper
check('DISCRIMINATING: tampered record breaks the chain verification', verifyLessonLedgerChain(tampered).ok === false);

// 3. Testar a recuperação indexada por efeito
const query1 = queryLessonsByEffect(root, {
  gatesFlipped: ['gates/atomic-exec-readonly-usability.proof.mjs:RED->GREEN'],
  decision: 'accept'
});

check('effect query returns matches', query1.length === 2);
check('ordered by sequence/score correctly', query1[0].lesson.sequence === 3 && query1[1].lesson.sequence === 1);
check('operator matched target files correctly', query1[0].lesson.operator.file === 'src/user.ts');

const query2 = queryLessonsByEffect(root, {
  targetFile: 'src/auth.ts',
  decision: 'reject'
});
check('file query returns reject lessons', query2.length === 1);
check('returns correct reason/operator', query2[0].lesson.operator.newText === 'class Authenticator');

// 4. Calcular precisão de recuperação (precision of recovery)
// Queremos achar o operador relevante para 'gates/atomic-exec-readonly-usability.proof.mjs:RED->GREEN'
const expectedFiles = new Set(['src/user.ts']);
let truePositives = 0;
for (const match of query1) {
  if (expectedFiles.has(match.lesson.operator.file)) {
    truePositives++;
  }
}
const precision = query1.length > 0 ? truePositives / query1.length : 0;
check('precision of recovery is calculated', precision > 0);

// Limpeza
fs.rmSync(root, { recursive: true, force: true });

if (json) {
  console.log(JSON.stringify({ ok: failures === 0, failures, lessonsRecorded: ledger.length, queryPrecision: precision, gate: 'lesson-ledger' }));
} else {
  console.log(failures === 0 ? `\nOK — lesson-ledger proof (0 failures, precision ${precision.toFixed(2)})` : `\nFAIL — lesson-ledger proof (${failures} failure(s))`);
}

process.exit(failures === 0 ? 0 : 1);
