export interface StringRewriteExample {
  input: string;
  output: string;
}

export interface StringReplaceSyGuSProblem {
  name?: string;
  examples: StringRewriteExample[];
  candidateNeedles?: string[];
  candidateReplacements?: string[];
}

export interface SyGuSProgramReceipt {
  logic: 'ALL';
  program: string;
  exampleCount: number;
  grammarOperators: string[];
  constants: string[];
}

function quote(value: string): string {
  return `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

function unique(values: string[]): string[] {
  return [...new Set(values.filter(Boolean))].sort();
}

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

export function buildStringReplaceSyGuS(problem: StringReplaceSyGuSProblem): SyGuSProgramReceipt {
  if (problem.examples.length === 0) throw new Error('SyGuS problem requires examples');
  const constants: string[] = [];
  for (const example of problem.examples) {
    constants.push(example.input, example.output);
    const change = diff(example.input, example.output);
    if (change) constants.push(change.before, change.after);
  }
  constants.push(...(problem.candidateNeedles ?? []), ...(problem.candidateReplacements ?? []));
  const stableConstants = unique(constants);
  const rewriteTerms = stableConstants
    .flatMap((needle) =>
      stableConstants.map((replacement) =>
        needle && needle !== replacement ? `(str.replace s ${quote(needle)} ${quote(replacement)})` : '',
      ),
    )
    .filter(Boolean);
  const terms = unique(['s', ...stableConstants.map(quote), ...rewriteTerms]);
  const name = (problem.name ?? 'atomic_meta_synth_string_replace').replace(/[^A-Za-z0-9_-]/g, '_');
  const program = [
    '(set-logic ALL)',
    `; Atomic meta-synthesis island: ${name}`,
    '(synth-fun rewrite ((s String)) String',
    '  ((Start String (',
    ...terms.map((term) => `    ${term}`),
    '  )))',
    ')',
    ...problem.examples.map((example) => `(constraint (= (rewrite ${quote(example.input)}) ${quote(example.output)}))`),
    '(check-synth)',
    '',
  ].join('\n');
  return {
    logic: 'ALL',
    program,
    exampleCount: problem.examples.length,
    grammarOperators: ['identity', 'constant', 'str.replace'],
    constants: stableConstants,
  };
}
