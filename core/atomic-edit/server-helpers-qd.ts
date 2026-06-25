import * as fs from 'node:fs';
import * as path from 'node:path';
import { type LessonRecord } from './server-helpers-lesson-ledger.js';

export interface BehaviorDescriptor {
  subsystem: 'server' | 'agent' | 'gates' | 'helpers' | 'other';
  changeType: 'create' | 'replace' | 'delete' | 'replace_text';
  effectClass: 'accept' | 'reject';
}

export interface MapElitesCell {
  descriptor: BehaviorDescriptor;
  candidateId: string;
  fitness: number; // Métrica: ex: delta de tempo (menor tempo de execução = maior fitness)
  lessonId: string;
  timestamp: number;
}

function archivePath(repoRoot: string): string {
  const dir = path.join(repoRoot, '.atomic');
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  return path.join(dir, 'map-elites-archive.json');
}

export function computeBehaviorDescriptor(lesson: LessonRecord): BehaviorDescriptor {
  const file = lesson.operator.file.replaceAll('\\', '/');
  let subsystem: BehaviorDescriptor['subsystem'] = 'other';
  if (file.startsWith('gates/') || file.includes('/gates/')) {
    subsystem = 'gates';
  } else if (file.includes('agent/')) {
    subsystem = 'agent';
  } else if (file.startsWith('server-helpers-')) {
    subsystem = 'helpers';
  } else if (file.startsWith('server.ts') || file.startsWith('server-tools-')) {
    subsystem = 'server';
  }

  return {
    subsystem,
    changeType: lesson.operator.op,
    effectClass: lesson.decision,
  };
}

export function computeFitness(lesson: LessonRecord): number {
  const duration = lesson.context.durationMs ?? 1000;
  // Minimizar o tempo de execução (quanto menor o tempo, maior o fitness)
  return Math.max(1, Math.floor(1000000 / duration));
}

export function getMapElitesArchive(repoRoot: string): MapElitesCell[] {
  try {
    const file = archivePath(repoRoot);
    if (!fs.existsSync(file)) return [];
    return JSON.parse(fs.readFileSync(file, 'utf8')) as MapElitesCell[];
  } catch {
    return [];
  }
}

export function updateMapElitesArchive(
  repoRoot: string,
  lesson: LessonRecord
): { admitted: boolean; isNewCell: boolean; isImprovement: boolean } {
  try {
    const file = archivePath(repoRoot);
    const archive = getMapElitesArchive(repoRoot);
    const descriptor = computeBehaviorDescriptor(lesson);
    const fitness = computeFitness(lesson);

    const cellKey = (d: BehaviorDescriptor) => `${d.subsystem}::${d.changeType}::${d.effectClass}`;
    const targetKey = cellKey(descriptor);

    let foundIndex = -1;
    for (let i = 0; i < archive.length; i++) {
      if (cellKey(archive[i].descriptor) === targetKey) {
        foundIndex = i;
        break;
      }
    }

    let admitted = false;
    let isNewCell = false;
    let isImprovement = false;

    if (foundIndex === -1) {
      // Célula vazia (nova dimensão de comportamento preenchida)
      isNewCell = true;
      admitted = true;
      archive.push({
        descriptor,
        candidateId: lesson.lessonId,
        fitness,
        lessonId: lesson.lessonId,
        timestamp: Date.now(),
      });
    } else {
      // Célula já ocupada: admite apenas se o novo candidato for superior na métrica de fitness (otimização local)
      const current = archive[foundIndex];
      if (fitness > current.fitness) {
        isImprovement = true;
        admitted = true;
        archive[foundIndex] = {
          descriptor,
          candidateId: lesson.lessonId,
          fitness,
          lessonId: lesson.lessonId,
          timestamp: Date.now(),
        };
      }
    }

    if (admitted) {
      fs.writeFileSync(file, JSON.stringify(archive, null, 2) + '\n');
    }

    return { admitted, isNewCell, isImprovement };
  } catch {
    return { admitted: false, isNewCell: false, isImprovement: false };
  }
}

export function computeMapElitesMetrics(archive: MapElitesCell[]): {
  cellsFilled: number;
  averageFitness: number;
} {
  if (archive.length === 0) return { cellsFilled: 0, averageFitness: 0 };
  const sum = archive.reduce((acc, c) => acc + c.fitness, 0);
  return {
    cellsFilled: archive.length,
    averageFitness: Math.floor(sum / archive.length),
  };
}
