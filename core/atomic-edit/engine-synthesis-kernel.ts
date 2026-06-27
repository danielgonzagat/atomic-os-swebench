import * as childProcess from 'node:child_process';
import { createHash } from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { runCvc5SyGuS } from './engine-cvc5-sygus.js';
import { buildStringReplaceSyGuS } from './engine-sygus.js';

export type SynthesisVerdict =
  | 'PROVEN'
  | 'UNSAT'
  | 'UNKNOWN'
  | 'ABSENT'
  | 'INVALID'
  | 'HEURISTIC_UNPROVEN';

export type SynthesisBackend = 'cvc5-sygus' | 'z3' | 'heuristic' | string;
export type SynthesisAuthority = 'formal' | 'heuristic' | 'none';

export interface SynthesisProblem {
  kind: 'cover' | 'rewrite' | 'invariant' | 'operator' | 'gate' | string;
  intent: string;
  source: Record<string, unknown>;
  domain: string;
  variables: Array<Record<string, unknown>>;
  constraints: Array<Record<string, unknown>>;
  objective: 'minimize' | 'satisfy' | 'synthesize' | 'prove' | 'classify' | string;
  limits: {
    timeoutMs: number;
    maxCandidates: number;
    grammarDepth: number;
    backends: SynthesisBackend[];
  };
  problemSha256?: string;
}

export interface Candidate {
  candidateSha256?: string;
  problemSha256?: string;
  backend: SynthesisBackend;
  payload: unknown;
  renderedArtifact?: string;
  limits?: Record<string, unknown>;
  authority: SynthesisAuthority;
}

export interface BackendAttempt {
  backend: SynthesisBackend;
  verdict: SynthesisVerdict;
  authority: SynthesisAuthority;
  evidence: Record<string, unknown>;
  candidates: Candidate[];
}

export interface ProofReceipt extends BackendAttempt {
  schemaVersion: 1;
  problemSha256: string;
  problem: SynthesisProblem;
  candidates: Candidate[];
  receiptSha256: string;
}

export interface SynthesisKernelOptions {
  repoRoot?: string;
  allowCvc5?: boolean;
  cvc5Bin?: string;
  env?: NodeJS.ProcessEnv;
}

export interface SynthesisKernelResult {
  ok: boolean;
  problem: SynthesisProblem & { problemSha256: string };
  receipts: ProofReceipt[];
  promotionEligible: boolean;
}

const here = path.dirname(fileURLToPath(import.meta.url));

function findRepoRoot(start: string): string {
  let current = start;
  for (let i = 0; i < 8; i += 1) {
    if (fs.existsSync(path.join(current, 'formal', 'atomic-algebra', 'coupling_cover_z3.py'))) return current;
    const parent = path.dirname(current);
    if (parent === current) break;
    current = parent;
  }
  return path.resolve(start, '..', '..');
}

const repoRootDefault = findRepoRoot(here);

function semanticProblem(problem: SynthesisProblem): SynthesisProblem {
  const { problemSha256: _problemSha256, ...semantic } = problem;
  return semantic as SynthesisProblem;
}

function semanticCandidate(candidate: Candidate): Candidate {
  const {
    candidateSha256: _candidateSha256,
    problemSha256: _problemSha256,
    ...semantic
  } = candidate;
  return semantic as Candidate;
}

export function canonicalJson(value: unknown): string {
  if (value === undefined || value === null) return 'null';
  if (Array.isArray(value)) return '[' + value.map(canonicalJson).join(',') + ']';
  if (typeof value === 'object') {
    const record = value as Record<string, unknown>;
    return (
      '{' +
      Object.keys(record)
        .filter((key) => record[key] !== undefined)
        .sort()
        .map((key) => JSON.stringify(key) + ':' + canonicalJson(record[key]))
        .join(',') +
      '}'
    );
  }
  return JSON.stringify(value);
}

export function sha256(value: unknown): string {
  return createHash('sha256').update(typeof value === 'string' ? value : canonicalJson(value)).digest('hex');
}

export function hashSynthesisProblem(problem: SynthesisProblem): string {
  return sha256(semanticProblem(problem));
}

export function hashCandidate(candidate: Candidate): string {
  return sha256(semanticCandidate(candidate));
}

export function makeProofReceipt(opts: {
  problem: SynthesisProblem;
  backend: SynthesisBackend;
  verdict: SynthesisVerdict;
  authority: SynthesisAuthority;
  evidence: Record<string, unknown>;
  candidates: Candidate[];
}): ProofReceipt {
  const problemSha256 = hashSynthesisProblem(opts.problem);
  const problem = { ...semanticProblem(opts.problem), problemSha256 };
  const candidates = opts.candidates.map((candidate) => {
    const normalized: Candidate = {
      ...semanticCandidate(candidate),
      backend: candidate.backend ?? opts.backend,
      authority: candidate.authority,
      problemSha256,
    };
    return { ...normalized, candidateSha256: hashCandidate(normalized) };
  });
  const body = {
    schemaVersion: 1 as const,
    problemSha256,
    problem,
    backend: opts.backend,
    verdict: opts.verdict,
    authority: opts.authority,
    evidence: opts.evidence,
    candidates,
  };
  return { ...body, receiptSha256: sha256(body) };
}

export function verifyProofReceipt(receipt: ProofReceipt): { ok: true } | { ok: false; error: string } {
  const { receiptSha256, ...body } = receipt;
  const expectedHash = sha256(body);
  if (receiptSha256 !== expectedHash) return { ok: false, error: 'receiptSha256 mismatch' };
  if (receipt.problemSha256 !== hashSynthesisProblem(receipt.problem)) {
    return { ok: false, error: 'problemSha256 mismatch' };
  }
  for (const candidate of receipt.candidates) {
    if (candidate.candidateSha256 !== hashCandidate(candidate)) {
      return { ok: false, error: 'candidateSha256 mismatch' };
    }
  }
  return { ok: true };
}

export function promotionEligible(receipt: ProofReceipt): boolean {
  return receipt.verdict === 'PROVEN' && receipt.authority === 'formal' && verifyProofReceipt(receipt).ok === true;
}

function couplingConstraints(problem: SynthesisProblem): Array<[string, string]> {
  return problem.constraints
    .filter((constraint) => constraint.op === 'coupling')
    .map((constraint) => [String(constraint.antecedent), String(constraint.consequent)]);
}

function exampleConstraints(problem: SynthesisProblem): Array<{ input: string; output: string }> {
  return problem.constraints
    .filter((constraint) => constraint.op === 'example')
    .map((constraint) => ({ input: String(constraint.input), output: String(constraint.output) }));
}

function runZ3Cover(problem: SynthesisProblem, options: SynthesisKernelOptions): ProofReceipt {
  const repoRoot = options.repoRoot ?? repoRootDefault;
  const script = path.join(repoRoot, 'formal', 'atomic-algebra', 'coupling_cover_z3.py');
  if (!fs.existsSync(script)) {
    return makeProofReceipt({
      problem,
      backend: 'z3',
      verdict: 'ABSENT',
      authority: 'none',
      evidence: { reason: 'coupling_cover_z3.py not found', script },
      candidates: [],
    });
  }

  const venvPython = path.join(repoRoot, '.z3venv', 'bin', 'python3');
  const python = fs.existsSync(venvPython) ? venvPython : 'python3';
  const couplings = couplingConstraints(problem);
  const res = childProcess.spawnSync(python, [script], {
    input: JSON.stringify({ couplings }),
    encoding: 'utf8',
    timeout: problem.limits.timeoutMs,
  });
  if (res.error || res.status === null) {
    return makeProofReceipt({
      problem,
      backend: 'z3',
      verdict: 'ABSENT',
      authority: 'none',
      evidence: { reason: 'z3 runner unavailable', error: res.error?.message ?? 'no exit', python, script },
      candidates: [],
    });
  }

  const last = String(res.stdout ?? '').trim().split(String.fromCharCode(10)).filter(Boolean).pop() ?? '';
  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(last) as Record<string, unknown>;
  } catch {
    return makeProofReceipt({
      problem,
      backend: 'z3',
      verdict: 'UNKNOWN',
      authority: 'none',
      evidence: { reason: 'unparseable z3 output', stdout: res.stdout, stderr: res.stderr, python, script },
      candidates: [],
    });
  }

  if (parsed.status === 'PROVEN' && parsed.optimal_proven === true) {
    const candidate: Candidate = {
      backend: 'z3',
      authority: 'formal',
      payload: { optimal: parsed.optimal, size: parsed.size, universe: parsed.universe },
    };
    return makeProofReceipt({
      problem,
      backend: 'z3',
      verdict: 'PROVEN',
      authority: 'formal',
      evidence: { ...parsed, python, script },
      candidates: [candidate],
    });
  }

  const status: SynthesisVerdict =
    parsed.status === 'UNSAT' ? 'UNSAT' : parsed.status === 'ABSENT' ? 'ABSENT' : 'UNKNOWN';
  return makeProofReceipt({
    problem,
    backend: 'z3',
    verdict: status,
    authority: 'none',
    evidence: { ...parsed, python, script, stderr: res.stderr },
    candidates: [],
  });
}

function runHeuristic(problem: SynthesisProblem): ProofReceipt {
  const examples = exampleConstraints(problem);
  const candidate: Candidate | null = examples.length
    ? {
        backend: 'heuristic',
        authority: 'heuristic',
        payload: { examples, reason: 'bounded example enumerator candidate' },
      }
    : null;
  return makeProofReceipt({
    problem,
    backend: 'heuristic',
    verdict: 'HEURISTIC_UNPROVEN',
    authority: 'heuristic',
    evidence: { reason: 'heuristic candidate has no formal authority', exampleCount: examples.length },
    candidates: candidate ? [candidate] : [],
  });
}

function runCvc5(problem: SynthesisProblem, options: SynthesisKernelOptions): ProofReceipt {
  const examples = exampleConstraints(problem);
  const sygus = examples.length
    ? buildStringReplaceSyGuS({ name: String(problem.intent || 'atomic_synthesis'), examples })
    : { program: '(check-synth)\n', exampleCount: 0, grammarOperators: [], constants: [], logic: 'ALL' as const };
  const attempt = runCvc5SyGuS(sygus.program, {
    allowRun: options.allowCvc5 === true,
    cvc5Bin: options.cvc5Bin,
    timeoutMs: problem.limits.timeoutMs,
    env: options.env,
  });
  return makeProofReceipt({
    problem,
    backend: 'cvc5-sygus',
    verdict: attempt.verdict,
    authority: attempt.verdict === 'PROVEN' ? 'formal' : 'none',
    evidence: { ...attempt.evidence, sygus },
    candidates:
      attempt.verdict === 'PROVEN'
        ? [{ backend: 'cvc5-sygus', authority: 'formal', payload: { stdout: attempt.evidence.stdout } }]
        : [],
  });
}

export function runSynthesisKernel(
  rawProblem: SynthesisProblem,
  options: SynthesisKernelOptions = {},
): SynthesisKernelResult {
  const problemSha256 = hashSynthesisProblem(rawProblem);
  const problem = { ...semanticProblem(rawProblem), problemSha256 };
  const receipts = problem.limits.backends.map((backend) => {
    if (backend === 'z3') return runZ3Cover(problem, options);
    if (backend === 'cvc5-sygus') return runCvc5(problem, options);
    if (backend === 'heuristic') return runHeuristic(problem);
    return makeProofReceipt({
      problem,
      backend,
      verdict: 'UNKNOWN',
      authority: 'none',
      evidence: { reason: `unknown backend: ${backend}` },
      candidates: [],
    });
  });
  return {
    ok: receipts.every((receipt) => verifyProofReceipt(receipt).ok),
    problem,
    receipts,
    promotionEligible: receipts.some(promotionEligible),
  };
}
