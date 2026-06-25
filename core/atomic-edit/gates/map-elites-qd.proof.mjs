// map-elites-qd.proof.mjs — Adversarial proof gate for MAP-Elites Quality-Diversity selection (Fase 3).
// PROVES:
//   (1) computeBehaviorDescriptor correctly maps file location/op to subsystem and action;
//   (2) computeFitness appropriately scales with execution time (inverse mapping);
//   (3) updateMapElitesArchive handles empty cells (admission as new cell);
//   (4) updateMapElitesArchive selectively improves cell fitness only when the new candidate is superior;
//   (5) computeMapElitesMetrics returns correct cell count and average fitness.

import {
  updateMapElitesArchive,
  getMapElitesArchive,
  computeBehaviorDescriptor,
  computeFitness,
  computeMapElitesMetrics
} from '../dist/server-helpers-qd.js';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const json = process.argv.includes('--json');
let failures = 0;
function check(n, c) { const ok = !!c; if (!ok) failures += 1; if (!json) console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${n}`); }

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'map-elites-qd-proof-'));

// 1. Validar mapeamentos de BehaviorDescriptor
const l1 = {
  kind: 'atomic-effect-lesson-record',
  schemaVersion: 1,
  sequence: 1,
  previousRecordSha256: null,
  lessonId: 'lesson-1',
  operator: { file: 'gates/some-gate.proof.mjs', op: 'replace_text' },
  decision: 'accept',
  context: { durationMs: 200 }
};

const desc1 = computeBehaviorDescriptor(l1);
check('maps to gates subsystem', desc1.subsystem === 'gates');
check('maps to replace_text change type', desc1.changeType === 'replace_text');
check('maps to accept effect class', desc1.effectClass === 'accept');

const l2 = {
  kind: 'atomic-effect-lesson-record',
  schemaVersion: 1,
  sequence: 2,
  previousRecordSha256: 'sha-1',
  lessonId: 'lesson-2',
  operator: { file: 'server-helpers-io.ts', op: 'replace' },
  decision: 'reject',
  context: { durationMs: 500 }
};

const desc2 = computeBehaviorDescriptor(l2);
check('maps to helpers subsystem', desc2.subsystem === 'helpers');
check('maps to replace change type', desc2.changeType === 'replace');
check('maps to reject effect class', desc2.effectClass === 'reject');

// 2. Validar computação de Fitness
const fit1 = computeFitness(l1); // 1000000 / 200 = 5000
const fit2 = computeFitness(l2); // 1000000 / 500 = 2000
check('fitness is inversely proportional to duration', fit1 > fit2);
check('fitness calculated correctly for l1', fit1 === 5000);

// 3. Validar fluxo de atualização do arquivo MAP-Elites
// Teste 3a: Admissão de uma nova célula
const u1 = updateMapElitesArchive(root, l1);
check('admitted new cell', u1.admitted === true);
check('is marked as new cell', u1.isNewCell === true);
check('is not an improvement to an existing cell', u1.isImprovement === false);

const archiveAfterU1 = getMapElitesArchive(root);
check('archive has 1 cell', archiveAfterU1.length === 1);
check('archive cell has correct fitness', archiveAfterU1[0].fitness === 5000);

// Teste 3b: Rejeição de candidato com pior fitness para a mesma célula
const l1Pior = { ...l1, lessonId: 'lesson-1-pior', context: { durationMs: 400 } }; // fitness = 2500
const u2 = updateMapElitesArchive(root, l1Pior);
check('worse candidate rejected', u2.admitted === false);
check('not marked as new cell', u2.isNewCell === false);
check('not marked as improvement', u2.isImprovement === false);

const archiveAfterU2 = getMapElitesArchive(root);
check('archive still has 1 cell', archiveAfterU2.length === 1);
check('archive cell fitness unchanged', archiveAfterU2[0].fitness === 5000);

// Teste 3c: Aceitação de candidato com melhor fitness para a mesma célula (otimização)
const l1Melhor = { ...l1, lessonId: 'lesson-1-melhor', context: { durationMs: 100 } }; // fitness = 10000
const u3 = updateMapElitesArchive(root, l1Melhor);
check('better candidate admitted', u3.admitted === true);
check('not marked as new cell', u3.isNewCell === false);
check('marked as improvement', u3.isImprovement === true);

const archiveAfterU3 = getMapElitesArchive(root);
check('archive still has 1 cell', archiveAfterU3.length === 1);
check('archive cell fitness improved', archiveAfterU3[0].fitness === 10000);
check('archive cell candidateId updated', archiveAfterU3[0].candidateId === 'lesson-1-melhor');

// Teste 3d: Admissão de outra célula distinta
const u4 = updateMapElitesArchive(root, l2);
check('admitted distinct cell', u4.admitted === true && u4.isNewCell === true);

const archiveAfterU4 = getMapElitesArchive(root);
check('archive now has 2 cells', archiveAfterU4.length === 2);

// 4. Validar computação de métricas globais do arquivo
const metrics = computeMapElitesMetrics(archiveAfterU4);
check('cells filled count correct', metrics.cellsFilled === 2);
check('average fitness calculated correctly', metrics.averageFitness === Math.floor((10000 + 2000) / 2));

// Limpeza
fs.rmSync(root, { recursive: true, force: true });

if (json) {
  console.log(JSON.stringify({ ok: failures === 0, failures, cellsFilled: metrics.cellsFilled, avgFitness: metrics.averageFitness, gate: 'map-elites-qd' }));
} else {
  console.log(failures === 0 ? `\nOK — map-elites-qd proof (0 failures)` : `\nFAIL — map-elites-qd proof (${failures} failure(s))`);
}

process.exit(failures === 0 ? 0 : 1);
