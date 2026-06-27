import { describe, expect, it } from 'vitest';
import {
  canonicalJson,
  hashSynthesisProblem,
  makeProofReceipt,
  promotionEligible,
  runSynthesisKernel,
  verifyProofReceipt,
} from './engine-synthesis-kernel.js';
import { detectCvc5, runCvc5SyGuS } from './engine-cvc5-sygus.js';
import { synthesizeMetaOperator } from './engine-meta-synth.js';
import { buildStringReplaceSyGuS } from './engine-sygus.js';
import { registerToolsMetaSynth } from './server-tools-meta-synth.js';

const hex64 = /^[a-f0-9]{64}$/;
const pythonWithCvc5 = '/opt/homebrew/bin/python3';

function rewriteProblem() {
  return {
    kind: 'rewrite',
    intent: 'normalize colour spelling',
    source: { fixture: 'unit' },
    domain: 'ast-rewrite',
    variables: [{ name: 'input', type: 'String' }],
    constraints: [{ op: 'example', input: 'colour', output: 'color' }],
    objective: 'synthesize',
    limits: { timeoutMs: 1000, maxCandidates: 1, grammarDepth: 2, backends: ['heuristic'] },
  };
}

function coverProblem() {
  return {
    kind: 'cover',
    intent: 'cover coupled invariants',
    source: { fixture: 'unit' },
    domain: 'bool-cover',
    variables: [
      { name: 'A', type: 'Bool' },
      { name: 'B', type: 'Bool' },
    ],
    constraints: [{ op: 'coupling', antecedent: 'A', consequent: 'B' }],
    objective: 'minimize',
    limits: { timeoutMs: 5000, maxCandidates: 1, grammarDepth: 1, backends: ['z3'] },
  };
}

describe('neuro-symbolic synthesis kernel receipts', () => {
  it('hashes semantic objects canonically and rejects forged receipts', async () => {
    const problem = rewriteProblem();
    expect(canonicalJson({ b: 2, a: 1 })).toBe('{"a":1,"b":2}');
    expect(hashSynthesisProblem(problem)).toMatch(hex64);

    const receipt = makeProofReceipt({
      problem,
      backend: 'heuristic',
      verdict: 'HEURISTIC_UNPROVEN',
      authority: 'heuristic',
      evidence: { reason: 'enumerated from examples' },
      candidates: [],
    });

    expect(receipt.problemSha256).toMatch(hex64);
    expect(receipt.receiptSha256).toMatch(hex64);
    expect(verifyProofReceipt(receipt)).toEqual({ ok: true });
    expect(verifyProofReceipt({ ...receipt, receiptSha256: '0'.repeat(64) }).ok).toBe(false);
    expect(promotionEligible(receipt)).toBe(false);

    const formal = makeProofReceipt({
      problem,
      backend: 'z3',
      verdict: 'PROVEN',
      authority: 'formal',
      evidence: { optimal: ['color-normalizer'] },
      candidates: [{ backend: 'z3', payload: { operator: 'color-normalizer' }, authority: 'formal' }],
    });
    expect(promotionEligible(formal)).toBe(true);
    expect(promotionEligible({ ...formal, authority: 'heuristic' })).toBe(false);
    expect(promotionEligible({ ...formal, receiptSha256: '0'.repeat(64) })).toBe(false);
  });

  it('reports CVC5 absence as ABSENT with search evidence', async () => {
    const receipt = detectCvc5({ env: { PATH: '' }, candidatePaths: ['/definitely/not/cvc5'], pythonCandidates: [] });
    expect(receipt.verdict).toBe('ABSENT');
    expect(receipt.evidence.checked).toContain('/definitely/not/cvc5');
    expect(receipt.evidence.reason).toContain('cvc5');
  });

  it('detects the installed Python cvc5 module as a CVC5 backend', async () => {
    const receipt = detectCvc5({
      env: { ...process.env, PATH: '' },
      candidatePaths: [],
      pythonCandidates: [pythonWithCvc5],
    });
    expect(receipt.verdict).toBe('UNKNOWN');
    expect(receipt.evidence.source).toBe('python-module');
    expect(receipt.evidence.pythonBin).toBe(pythonWithCvc5);
    expect(receipt.evidence.version).toBe('1.3.4');
  });

  it('represents a SyGuS string rewrite problem', async () => {
    const program = buildStringReplaceSyGuS({
      name: 'colour_to_color',
      examples: [{ input: 'colour', output: 'color' }],
      candidateNeedles: ['colour'],
      candidateReplacements: ['color'],
    });
    expect(program.program).toContain('(check-synth)');
    expect(program.program).toContain('str.replace');
  });

  it('runs SyGuS through the installed Python cvc5 API', async () => {
    const attempt = runCvc5SyGuS('(check-synth)\n', {
      allowRun: true,
      env: { ...process.env, PATH: '' },
      candidatePaths: [],
      pythonCandidates: [pythonWithCvc5],
      examples: [
        { input: 'accent-colour', output: 'accent-color' },
        { input: 'button-colour', output: 'button-color' },
      ],
      candidateNeedles: ['colour'],
      candidateReplacements: ['color'],
    });
    expect(attempt.verdict).toBe('PROVEN');
    expect(attempt.evidence.source).toBe('python-module');
    expect(String(attempt.evidence.stdout)).toContain('str.replace');
  });

  it('classifies heuristic candidates as HEURISTIC_UNPROVEN', async () => {
    const result = runSynthesisKernel(rewriteProblem());
    expect(result.receipts[0].verdict).toBe('HEURISTIC_UNPROVEN');
    expect(result.receipts[0].authority).toBe('heuristic');
    expect(promotionEligible(result.receipts[0])).toBe(false);
  });

  it('wraps the Z3 cover backend as a real PROVEN receipt', async () => {
    const result = runSynthesisKernel(coverProblem());
    const receipt = result.receipts[0];
    expect(receipt.verdict).toBe('PROVEN');
    expect(receipt.backend).toBe('z3');
    expect(receipt.authority).toBe('formal');
    expect(receipt.evidence.optimal).toEqual(['B']);
    expect(verifyProofReceipt(receipt)).toEqual({ ok: true });
    expect(promotionEligible(receipt)).toBe(true);
  });

  it('returns MCP-safe receipts without direct write authority', async () => {
    const result = synthesizeMetaOperator(undefined, { allowCvc5: false });
    expect(result.problem.problemSha256).toMatch(hex64);
    expect(result.problem.kind).toBe('rewrite');
    expect(result.operator?.pattern).toBe('colour');
    expect(result.operator?.replacement).toBe('color');
    expect(result.train.passed).toBe(result.train.total);
    expect(result.heldOut.passed).toBe(result.heldOut.total);
    expect(result.receipts.length).toBeGreaterThan(0);
    expect(result.receipts.map((receipt: any) => receipt.verdict)).toContain('HEURISTIC_UNPROVEN');
    for (const receipt of result.receipts) {
      expect(receipt.receiptSha256).toMatch(hex64);
    }
    expect(result).toHaveProperty('promotionEligible');
    expect(result.promotionEligible).toBe(false);
    expect(result.proofLimits.length).toBeGreaterThan(0);
    expect(result.proofLimits.join('\n')).toMatch(/formal.*PROVEN/i);
    expect(JSON.stringify(result)).not.toContain('writeFileSync');
  });

  it('uses Python cvc5 as a formal backend when explicitly enabled', async () => {
    const result = synthesizeMetaOperator(undefined, {
      allowCvc5: true,
      pythonBin: pythonWithCvc5,
    });
    const cvc5Receipt = result.receipts.find((receipt: any) => receipt.backend === 'cvc5-sygus');
    expect(cvc5Receipt?.verdict).toBe('PROVEN');
    expect(cvc5Receipt?.authority).toBe('formal');
    expect(result.promotionEligible).toBe(true);
  });

  it('exports the Atomic MCP meta-synthesis registration surface', () => {
    expect(typeof registerToolsMetaSynth).toBe('function');
  });
});
