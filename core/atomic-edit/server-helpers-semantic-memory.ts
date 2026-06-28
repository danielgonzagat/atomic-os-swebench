import * as fs from 'node:fs';
import * as path from 'node:path';
import { createHash } from 'node:crypto';

const MAX_LEDGER_BYTES = 512 * 1024;
const MAX_LEDGER_LINES = 400;
const MAX_MATCHES = 5;
const MAX_TOKENS = 24;

const sha256 = (s: string): string => createHash('sha256').update(s).digest('hex');

export interface SemanticMemoryRecallMatch {
  source: 'lesson-ledger' | 'semantic-memory-ledger';
  score: number;
  id: string;
  file?: string;
  decision?: string;
  intent?: string;
  op?: string;
  gatesFlipped?: string[];
  recordSha256?: string;
  hash?: string;
  verified?: boolean;
}

export interface SemanticMemoryRecallEvidence {
  status: 'hit' | 'miss' | 'unavailable';
  query: { file: string; beforeSha256: string; afterSha256: string; tokens: string[] };
  sources: string[];
  matches: SemanticMemoryRecallMatch[];
  digest: string;
  note?: string;
}

function stableJson(value: unknown): string {
  if (value === undefined) return 'null';
  if (value === null || typeof value !== 'object') return JSON.stringify(value) ?? 'null';
  if (Array.isArray(value)) return '[' + value.map((item) => stableJson(item)).join(',') + ']';
  const record = value as Record<string, unknown>;
  return '{' + Object.keys(record).sort().map((key) => JSON.stringify(key) + ':' + stableJson(record[key])).join(',') + '}';
}

function digestEvidence(value: unknown): string {
  return sha256(stableJson(value));
}

function normalizeRelPath(value: string): string {
  let out = value.replaceAll('\\', '/');
  while (out.startsWith('./')) out = out.slice(2);
  while (out.endsWith('/')) out = out.slice(0, -1);
  return out === '.' ? '' : out;
}

function changedText(before: string, after: string): string {
  let prefix = 0;
  while (prefix < before.length && prefix < after.length && before[prefix] === after[prefix]) prefix++;
  let beforeEnd = before.length;
  let afterEnd = after.length;
  while (beforeEnd > prefix && afterEnd > prefix && before[beforeEnd - 1] === after[afterEnd - 1]) {
    beforeEnd--;
    afterEnd--;
  }
  return before.slice(prefix, beforeEnd).slice(0, 2000) + '\n' + after.slice(prefix, afterEnd).slice(0, 2000);
}

function queryTokens(file: string, before: string, after: string): string[] {
  const raw = (file + '\n' + changedText(before, after)).toLowerCase().match(/[a-z0-9_.\/-]{3,}/g) ?? [];
  const out: string[] = [];
  const seen = new Set<string>();
  for (const token of raw) {
    let normalized = token;
    if (normalized.startsWith('./')) normalized = normalized.slice(2);
    while (normalized.endsWith('.') || normalized.endsWith('/') || normalized.endsWith('-')) {
      normalized = normalized.slice(0, -1);
    }
    if (normalized.length < 3 || seen.has(normalized)) continue;
    seen.add(normalized);
    out.push(normalized);
    if (out.length >= MAX_TOKENS) break;
  }
  return out;
}

function objectRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : null;
}

function stringValue(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim() ? value : undefined;
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string' && item.length > 0) : [];
}

function compact(value: unknown): string | undefined {
  const text = stringValue(value);
  if (!text) return undefined;
  return text.length <= 240 ? text : text.slice(0, 237) + '...';
}

function verifyRecordHash(record: Record<string, unknown>, hashField: string): string | null {
  const expected = stringValue(record[hashField]);
  if (!expected) return null;
  const body: Record<string, unknown> = {};
  for (const key of Object.keys(record)) {
    if (key !== hashField) body[key] = record[key];
  }
  return sha256(JSON.stringify(body)) === expected ? expected : null;
}

function readJsonlTail(file: string): Record<string, unknown>[] {
  try {
    if (!fs.existsSync(file)) return [];
    const stat = fs.statSync(file);
    if (!stat.isFile() || stat.size <= 0) return [];
    const length = Math.min(stat.size, MAX_LEDGER_BYTES);
    const start = Math.max(0, stat.size - length);
    const buffer = Buffer.alloc(length);
    const fd = fs.openSync(file, 'r');
    try {
      fs.readSync(fd, buffer, 0, length, start);
    } finally {
      fs.closeSync(fd);
    }
    const lines = buffer.toString('utf8').split('\n');
    if (start > 0 && lines.length > 0) lines.shift();
    const records: Record<string, unknown>[] = [];
    for (const line of lines.filter(Boolean).slice(-MAX_LEDGER_LINES)) {
      try {
        const parsed = JSON.parse(line) as unknown;
        const record = objectRecord(parsed);
        if (record) records.push(record);
      } catch {
        /* malformed historical line: not producer-independent evidence */
      }
    }
    return records;
  } catch {
    return [];
  }
}

function recallAtomicDirs(repoRoot: string): string[] {
  const candidates = [
    path.join(repoRoot, '.atomic'),
    path.join(repoRoot, 'core', 'atomic-edit', '.atomic'),
  ];
  const seen = new Set<string>();
  const dirs: string[] = [];
  for (const candidate of candidates) {
    const resolved = path.resolve(candidate);
    if (seen.has(resolved) || !fs.existsSync(resolved)) continue;
    seen.add(resolved);
    dirs.push(resolved);
  }
  return dirs;
}

function tokenScore(tokens: string[], haystack: string, weight: number): number {
  const lower = haystack.toLowerCase();
  let score = 0;
  for (const token of tokens) {
    if (lower.includes(token)) score += weight;
  }
  return score;
}

function fileScore(candidate: string | undefined, target: string, targetBase: string): number {
  if (!candidate) return 0;
  const normalized = normalizeRelPath(candidate);
  if (normalized === target) return 50;
  return path.basename(normalized) === targetBase ? 10 : 0;
}

function lessonMatch(record: Record<string, unknown>, relPath: string, targetBase: string, tokens: string[]): SemanticMemoryRecallMatch | null {
  const recordSha256 = verifyRecordHash(record, 'recordSha256');
  if (!recordSha256) return null;
  const effect = objectRecord(record.effect);
  const operator = objectRecord(record.operator);
  const context = objectRecord(record.context);
  const gatesFlipped = stringArray(effect?.gatesFlipped);
  const file = stringValue(operator?.file);
  const op = stringValue(operator?.op);
  const decision = stringValue(record.decision);
  const intent = compact(context?.intent ?? context?.preflightError);
  const haystack = [file, op, decision, intent, stringValue(operator?.oldText), stringValue(operator?.newText), gatesFlipped.join(' ')].filter(Boolean).join('\n');
  const score = fileScore(file, relPath, targetBase) + tokenScore(tokens, haystack, 2) + (gatesFlipped.length > 0 ? 3 : 0);
  if (score <= 0) return null;
  return {
    source: 'lesson-ledger',
    score,
    id: stringValue(record.lessonId) ?? recordSha256,
    file,
    decision,
    intent,
    op,
    gatesFlipped,
    recordSha256,
    verified: true,
  };
}

function memoryMatch(record: Record<string, unknown>, relPath: string, targetBase: string, tokens: string[]): SemanticMemoryRecallMatch | null {
  const hash = verifyRecordHash(record, 'hash');
  if (!hash) return null;
  if (stringValue(record.tool) !== 'memory_record') return null;
  const files = stringArray(record.files);
  const tags = stringArray(record.tags);
  const symbols = stringArray(record.symbols);
  const intent = compact(record.intent);
  const normalizedFiles = files.map(normalizeRelPath);
  let score = 0;
  if (normalizedFiles.includes(relPath)) score += 50;
  if (normalizedFiles.some((file) => path.basename(file) === targetBase)) score += 10;
  const haystack = [intent, ...normalizedFiles, ...tags, ...symbols].filter(Boolean).join('\n');
  score += tokenScore(tokens, haystack, 2);
  if (score <= 0) return null;
  return {
    source: 'semantic-memory-ledger',
    score,
    id: hash,
    file: normalizedFiles[0],
    intent,
    hash,
    verified: true,
  };
}

function ranked(matches: SemanticMemoryRecallMatch[]): SemanticMemoryRecallMatch[] {
  return matches.sort((a, b) => b.score - a.score || a.source.localeCompare(b.source) || a.id.localeCompare(b.id)).slice(0, MAX_MATCHES);
}

export function recallSemanticMemory(repoRoot: string, file: string, before: string, after: string): SemanticMemoryRecallEvidence {
  const relFile = normalizeRelPath(file);
  const query = { file: relFile, beforeSha256: sha256(before), afterSha256: sha256(after), tokens: queryTokens(relFile, before, after) };
  try {
    const sources = new Set<string>();
    const matches: SemanticMemoryRecallMatch[] = [];
    for (const atomicDir of recallAtomicDirs(repoRoot)) {
      const lessonLedger = path.join(atomicDir, 'lesson-ledger.jsonl');
      if (fs.existsSync(lessonLedger)) {
        sources.add('lesson-ledger');
        for (const record of readJsonlTail(lessonLedger)) {
          const match = lessonMatch(record, relFile, path.basename(relFile), query.tokens);
          if (match) matches.push(match);
        }
      }
      const memoryLedger = path.join(atomicDir, 'semantic-memory-ledger.jsonl');
      if (fs.existsSync(memoryLedger)) {
        sources.add('semantic-memory-ledger');
        for (const record of readJsonlTail(memoryLedger)) {
          const match = memoryMatch(record, relFile, path.basename(relFile), query.tokens);
          if (match) matches.push(match);
        }
      }
    }
    const sourceList = [...sources].sort();
    const selected = ranked(matches);
    const body = { query, sources: sourceList, matches: selected };
    return {
      status: selected.length > 0 ? 'hit' : 'miss',
      query,
      sources: sourceList,
      matches: selected,
      digest: digestEvidence(body),
    };
  } catch (e) {
    const body = { query, sources: [], matches: [], note: e instanceof Error ? e.message : String(e) };
    return {
      status: 'unavailable',
      query,
      sources: [],
      matches: [],
      digest: digestEvidence(body),
      note: body.note,
    };
  }
}
