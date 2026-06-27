import {
  hashSynthesisProblem,
  promotionEligible as receiptPromotionEligible,
  runSynthesisKernel,
  type SynthesisProblem,
} from './engine-synthesis-kernel.js';
import { buildStringReplaceSyGuS, type StringRewriteExample } from './engine-sygus.js';

export interface IslandProblem {
  name: string;
  train: StringRewriteExample[];
  heldOut: StringRewriteExample[];
}

export interface EvalResult {
  passed: number;
  total: number;
  failures: Array<{ input: string; expected: string; actual: string }>;
}

export const DEFAULT_STRING_REPLACE_ISLAND: IslandProblem = {
  name: 'string_replace_colour_to_color',
  train: [
    { input: 'const label = "colour";', output: 'const label = "color";' },
    { input: 'theme.colour = user.colour;', output: 'theme.color = user.color;' },
    { input: 'return format("colour-mode");', output: 'return format("color-mode");' },
  ],
  heldOut: [
    { input: 'export const defaultColour = "colour";', output: 'export const defaultColour = "color";' },
    { input: 'if (field === "colour") return field;', output: 'if (field === "color") return field;' },
    { input: 'button.dataset.colour = "accent-colour";', output: 'button.dataset.color = "accent-color";' },
    { input: '/* colour should be normalized */', output: '/* color should be normalized */' },
  ],
};

function diff(input: string, output: string): { before: string; after: string } | null {
  let start = 0;
  while (start < input.length && start < output.length && input[start] === output[start]) start += 1;
  let inputEnd = input.length;
  let outputEnd = output.length;
  while (inputEnd > start && outputEnd > start && input[inputEnd - 1] === output[outputEnd - 1]) {
    inputEnd -= 1;
    outputEnd -= 1;
  }
  const before = input.slice(start, inputEnd);
  const after = output.slice(start, outputEnd);
  return before || after ? { before, after } : null;
}

function apply(input: string, pattern: string, replacement: string): string {
  return input.split(pattern).join(replacement);
}

function evaluate(examples: StringRewriteExample[], pattern: string, replacement: string): EvalResult {
  const failures: EvalResult['failures'] = [];
  for (const example of examples) {
    const actual = apply(example.input, pattern, replacement);
    if (actual !== example.output) failures.push({ input: example.input, expected: example.output, actual });
  }
  return { passed: examples.length - failures.length, total: examples.length, failures };
}

function candidate(problem: IslandProblem): { pattern: string; replacement: string } | null {
  const seen = new Map<string, { pattern: string; replacement: string }>();
  for (const example of problem.train) {
    const change = diff(example.input, example.output);
    if (change && change.before && change.before !== change.after) {
      seen.set(`${change.before}\u0000${change.after}`, { pattern: change.before, replacement: change.after });
    }
  }
  for (const item of seen.values()) {
    if (evaluate(problem.train, item.pattern, item.replacement).passed === problem.train.length) return item;
  }
  return null;
}

function makeProblem(problem: IslandProblem, backends: string[]): SynthesisProblem & { problemSha256: string } {
  const raw: SynthesisProblem = {
    kind: 'rewrite',
    intent: problem.name,
    source: { island: problem.name, trainCount: problem.train.length, heldOutCount: problem.heldOut.length },
    domain: 'ast-rewrite',
    variables: [{ name: 'input', type: 'String' }],
    constraints: problem.train.map((example) => ({ op: 'example', input: example.input, output: example.output })),
    objective: 'synthesize',
    limits: { timeoutMs: 5000, maxCandidates: 1, grammarDepth: 2, backends },
  };
  return { ...raw, problemSha256: hashSynthesisProblem(raw) };
}

export function synthesizeMetaOperator(
  problem: IslandProblem = DEFAULT_STRING_REPLACE_ISLAND,
  options: { allowCvc5?: boolean; cvc5Bin?: string } = {},
) {
  if (problem.train.length === 0 || problem.heldOut.length === 0) {
    throw new Error('meta-synthesis requires train and held-out examples');
  }
  const found = candidate(problem);
  const train = found ? evaluate(problem.train, found.pattern, found.replacement) : { passed: 0, total: problem.train.length, failures: [] };
  const heldOut = found
    ? evaluate(problem.heldOut, found.pattern, found.replacement)
    : { passed: 0, total: problem.heldOut.length, failures: [] };
  const backends = options.allowCvc5 === true ? ['heuristic', 'cvc5-sygus'] : ['heuristic'];
  const synthesisProblem = makeProblem(problem, backends);
  const sygus = buildStringReplaceSyGuS({
    name: problem.name,
    examples: problem.train,
    candidateNeedles: found ? [found.pattern] : [],
    candidateReplacements: found ? [found.replacement] : [],
  });
  const kernel = runSynthesisKernel(synthesisProblem, {
    allowCvc5: options.allowCvc5 === true,
    cvc5Bin: options.cvc5Bin,
  });
  const operator = found
    ? {
        id: `meta-${synthesisProblem.problemSha256.slice(0, 16)}`,
        kind: 'string.replace',
        source: 'cegis-enumerator',
        pattern: found.pattern,
        replacement: found.replacement,
        expression: `input.split(${JSON.stringify(found.pattern)}).join(${JSON.stringify(found.replacement)})`,
        authority: 'heuristic',
      }
    : null;
  const promotionEligible = kernel.receipts.some(receiptPromotionEligible);
  return {
    ok: kernel.ok && train.passed === train.total && heldOut.passed === heldOut.total,
    name: problem.name,
    island: 'string-replace',
    problem: synthesisProblem,
    operator,
    train,
    heldOut,
    sygus,
    receipts: kernel.receipts,
    promotionEligible,
    proofLimits: [
      'No backend writes directly to core/atomic-edit/**.',
      'Heuristic candidates remain HEURISTIC_UNPROVEN and are not promotion eligible.',
      'Only verified formal PROVEN receipts can enter automatic promotion consideration.',
      'atomic_self_evolution remains the admission boundary; atomic_expand_self remains the engine write boundary.',
    ],
  };
}
