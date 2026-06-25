import * as fs from 'node:fs';
import * as path from 'node:path';
import { createHash } from 'node:crypto';

const sha256 = (s: string): string => createHash('sha256').update(s).digest('hex');

export interface EffectSignature {
  gatesFlipped: string[]; // ex: ["gates/atomic-exec-readonly-usability.proof.mjs:RED->GREEN"]
  veredictDelta?: string; // ex: "RED->GREEN"
  floorDelta?: Array<{ file: string; bytesRemoved: number; bytesAdded: number; op: string }>;
}

export interface AppliedOperator {
  file: string;
  op: 'create' | 'replace' | 'delete' | 'replace_text';
  content?: string;
  oldText?: string;
  newText?: string;
  occurrence?: number;
}

export interface LessonRecord {
  kind: 'atomic-effect-lesson-record';
  schemaVersion: 1;
  sequence: number;
  previousRecordSha256: string | null;
  lessonId: string;
  effect: EffectSignature;
  operator: AppliedOperator;
  decision: 'accept' | 'reject';
  context: {
    intent?: string;
    preflightError?: string;
    durationMs?: number;
    ts?: number;
  };
  recordSha256?: string;
}

function ledgerPaths(repoRoot: string): { jsonl: string; head: string } {
  const dir = path.join(repoRoot, '.atomic');
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  return {
    jsonl: path.join(dir, 'lesson-ledger.jsonl'),
    head: path.join(dir, 'lesson-ledger.head'),
  };
}

export function readLessonLedger(repoRoot: string): LessonRecord[] {
  try {
    const { jsonl } = ledgerPaths(repoRoot);
    if (!fs.existsSync(jsonl)) return [];
    return fs
      .readFileSync(jsonl, 'utf8')
      .split('\n')
      .filter(Boolean)
      .map((l) => JSON.parse(l) as LessonRecord);
  } catch {
    return [];
  }
}

export function recordLesson(
  repoRoot: string,
  input: {
    effect: EffectSignature;
    operator: AppliedOperator;
    decision: 'accept' | 'reject';
    context?: LessonRecord['context'];
  }
): LessonRecord | null {
  try {
    const { jsonl, head } = ledgerPaths(repoRoot);
    let prevSha: string | null = null;
    try {
      if (fs.existsSync(head)) prevSha = fs.readFileSync(head, 'utf8').trim() || null;
    } catch {
      prevSha = null;
    }
    
    // fallback se o head estiver ausente mas jsonl tiver registros
    if (!prevSha && fs.existsSync(jsonl)) {
      const records = readLessonLedger(repoRoot);
      if (records.length > 0) {
        prevSha = records[records.length - 1].recordSha256 ?? null;
      }
    }

    const sequence = prevSha ? readLessonLedger(repoRoot).length + 1 : 1;

    const body: Omit<LessonRecord, 'recordSha256'> = {
      kind: 'atomic-effect-lesson-record',
      schemaVersion: 1,
      sequence,
      previousRecordSha256: prevSha,
      lessonId: `lesson:${sha256(JSON.stringify(input.operator) + '-' + sequence).slice(0, 16)}`,
      effect: input.effect,
      operator: input.operator,
      decision: input.decision,
      context: input.context ?? {},
    };

    const recordSha = sha256(JSON.stringify(body));
    const fullRecord: LessonRecord = { ...body, recordSha256: recordSha };

    fs.appendFileSync(jsonl, JSON.stringify(fullRecord) + '\n');
    fs.writeFileSync(head, recordSha + '\n');
    return fullRecord;
  } catch {
    return null;
  }
}

/**
 * Consulta lições por efeito. Ordena por pontuação de relevância.
 */
export function queryLessonsByEffect(
  repoRoot: string,
  query: {
    gatesFlipped?: string[];
    targetFile?: string;
    decision?: 'accept' | 'reject';
  }
): Array<{ lesson: LessonRecord; score: number }> {
  const records = readLessonLedger(repoRoot);
  const results: Array<{ lesson: LessonRecord; score: number }> = [];

  for (const r of records) {
    if (query.decision && r.decision !== query.decision) continue;
    if (query.targetFile && r.operator.file !== query.targetFile) continue;

    let score = 0;
    if (query.gatesFlipped && query.gatesFlipped.length > 0) {
      const recordGates = new Set(r.effect.gatesFlipped);
      let matches = 0;
      for (const g of query.gatesFlipped) {
        if (recordGates.has(g)) {
          matches++;
        }
      }
      if (matches === 0) continue;
      score += matches * 10;
    }

    if (query.targetFile && r.operator.file === query.targetFile) {
      score += 5;
    }

    results.push({ lesson: r, score });
  }

  return results.sort((a, b) => b.score - a.score || b.lesson.sequence - a.lesson.sequence);
}

/**
 * Verifica se a cadeia de lições no disco está 100% íntegra (proof-carrying).
 */
export function verifyLessonLedgerChain(records: LessonRecord[]): { ok: boolean; error?: string } {
  let prevSha: string | null = null;
  for (let i = 0; i < records.length; i++) {
    const r = records[i];
    const { recordSha256, ...body } = r;
    if ((r.previousRecordSha256 ?? null) !== prevSha) {
      return { ok: false, error: `Chain break at sequence ${r.sequence}` };
    }
    const computed = sha256(JSON.stringify(body));
    if (recordSha256 !== computed) {
      return { ok: false, error: `Hash mismatch at sequence ${r.sequence}` };
    }
    prevSha = recordSha256 ?? null;
  }
  return { ok: true };
}
