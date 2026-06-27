import * as childProcess from 'node:child_process';
import * as fs from 'node:fs';
import type { SynthesisVerdict } from './engine-synthesis-kernel.js';

export interface Cvc5DetectionOptions {
  cvc5Bin?: string;
  candidatePaths?: string[];
  pythonBin?: string;
  pythonCandidates?: string[];
  env?: NodeJS.ProcessEnv;
  timeoutMs?: number;
}

export interface Cvc5Attempt {
  backend: 'cvc5-sygus';
  verdict: Extract<SynthesisVerdict, 'PROVEN' | 'UNSAT' | 'UNKNOWN' | 'ABSENT' | 'INVALID'>;
  evidence: {
    source?: 'cli' | 'python-module' | 'none';
    checked: string[];
    bin: string | null;
    pythonChecked?: string[];
    pythonBin?: string | null;
    modulePath?: string;
    reason: string;
    version?: string;
    stdout?: string;
    stderr?: string;
    exitCode?: number | null;
    signal?: NodeJS.Signals | null;
  };
}

export interface Cvc5SyGuSOptions extends Cvc5DetectionOptions {
  allowRun?: boolean;
  examples?: Array<{ input: string; output: string }>;
  candidateNeedles?: string[];
  candidateReplacements?: string[];
}

const DEFAULT_CVC5_PATHS = ['/opt/homebrew/bin/cvc5', '/usr/local/bin/cvc5', '/usr/bin/cvc5'];
const DEFAULT_PYTHON_PATHS = ['/opt/homebrew/bin/python3', '/usr/local/bin/python3', '/usr/bin/python3'];

function executable(file: string): boolean {
  try {
    fs.accessSync(file, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function unique(values: string[]): string[] {
  return [...new Set(values.filter(Boolean))];
}


function childEnv(env: NodeJS.ProcessEnv | undefined): NodeJS.ProcessEnv {
  return env ? { ...process.env, ...env } : process.env;
}


function pathCandidates(env: NodeJS.ProcessEnv): string[] {
  return String(env.PATH ?? '')
    .split(':')
    .filter(Boolean)
    .map((entry) => `${entry.replace(/\/+$/, '')}/cvc5`);
}

function pythonCandidates(options: Cvc5DetectionOptions, env: NodeJS.ProcessEnv): string[] {
  if (options.pythonCandidates) return unique([...(options.pythonBin ? [options.pythonBin] : []), ...options.pythonCandidates]);
  return unique([
    ...(options.pythonBin ? [options.pythonBin] : []),
    ...(env.CVC5_PYTHON_BIN ? [env.CVC5_PYTHON_BIN] : []),
    ...String(env.PATH ?? '')
      .split(':')
      .filter(Boolean)
      .map((entry) => `${entry.replace(/\/+$/, '')}/python3`),
    ...DEFAULT_PYTHON_PATHS,
  ]);
}

function probePythonCvc5(pythonBin: string, options: Cvc5DetectionOptions): null | {
  pythonBin: string;
  version: string;
  modulePath: string;
} {
  if (!executable(pythonBin)) return null;
  const probe = childProcess.spawnSync(
    pythonBin,
    [
      '-c',
      'import json, cvc5; print(json.dumps({"version": getattr(cvc5, "__version__", "unknown"), "modulePath": getattr(cvc5, "__file__", ""), "hasSolver": hasattr(cvc5, "Solver")}))',
    ],
    { encoding: 'utf8', timeout: options.timeoutMs ?? 3000, env: childEnv(options.env) },
  );
  if (probe.error || probe.status !== 0) return null;
  try {
    const parsed = JSON.parse(String(probe.stdout ?? '').trim()) as {
      version?: string;
      modulePath?: string;
      hasSolver?: boolean;
    };
    if (parsed.hasSolver !== true) return null;
    return { pythonBin, version: parsed.version ?? 'unknown', modulePath: parsed.modulePath ?? '' };
  } catch {
    return null;
  }
}

export function detectCvc5(options: Cvc5DetectionOptions = {}): Cvc5Attempt {
  const env = childEnv(options.env);
  const checked = unique([
    ...(options.cvc5Bin ? [options.cvc5Bin] : []),
    ...(env.CVC5_BIN ? [env.CVC5_BIN] : []),
    ...(options.candidatePaths ?? []),
    ...pathCandidates(env),
    ...DEFAULT_CVC5_PATHS,
  ]);

  for (const bin of checked) {
    if (!executable(bin)) continue;
    const version = childProcess.spawnSync(bin, ['--version'], {
      encoding: 'utf8',
      timeout: options.timeoutMs ?? 3000,
      env,
    });
    if (version.error || version.status !== 0) {
      return {
        backend: 'cvc5-sygus',
        verdict: 'UNKNOWN',
        evidence: {
          source: 'cli',
          checked,
          bin,
          reason: 'cvc5 executable found but version probe failed',
          stdout: version.stdout ?? '',
          stderr: version.stderr ?? '',
          exitCode: version.status,
          signal: version.signal,
        },
      };
    }
    return {
      backend: 'cvc5-sygus',
      verdict: 'UNKNOWN',
      evidence: {
        source: 'cli',
        checked,
        bin,
        reason: 'cvc5 executable detected; no SyGuS proof has been run yet',
        version: String(version.stdout || version.stderr || '').trim(),
        exitCode: version.status,
        signal: version.signal,
      },
    };
  }

  const pythonChecked = pythonCandidates(options, env);
  for (const pythonBin of pythonChecked) {
    const probe = probePythonCvc5(pythonBin, { ...options, env });
    if (!probe) continue;
    return {
      backend: 'cvc5-sygus',
      verdict: 'UNKNOWN',
      evidence: {
        source: 'python-module',
        checked,
        pythonChecked,
        bin: null,
        pythonBin: probe.pythonBin,
        version: probe.version,
        modulePath: probe.modulePath,
        reason: 'cvc5 Python module detected; no SyGuS proof has been run yet',
      },
    };
  }

  return {
    backend: 'cvc5-sygus',
    verdict: 'ABSENT',
    evidence: {
      source: 'none',
      checked,
      pythonChecked,
      bin: null,
      pythonBin: null,
      reason: 'cvc5 binary not found; set CVC5_BIN or provide cvc5Bin to enable SyGuS solving',
    },
  };
}

function runPythonCvc5SyGuS(detected: Cvc5Attempt, options: Cvc5SyGuSOptions): Cvc5Attempt {
  const pythonBin = detected.evidence.pythonBin;
  if (!pythonBin) return detected;
  const examples = options.examples ?? [];
  if (examples.length === 0) {
    return {
      backend: 'cvc5-sygus',
      verdict: 'UNKNOWN',
      evidence: {
        ...detected.evidence,
        reason: 'cvc5 Python module detected, but API runner requires concrete examples',
      },
    };
  }
  const script = String.raw`
import json, sys, traceback
try:
    import cvc5
    from cvc5 import Kind
    payload = json.load(sys.stdin)
    examples = payload.get("examples") or []
    needles = payload.get("candidateNeedles") or []
    replacements = payload.get("candidateReplacements") or []
    solver = cvc5.Solver()
    solver.setOption("sygus", "true")
    solver.setOption("incremental", "false")
    solver.setLogic("ALL")
    string_sort = solver.getStringSort()
    x = solver.mkVar(string_sort, "s")
    start = solver.mkVar(string_sort, "Start")
    grammar = solver.mkGrammar([x], [start])
    constants = set([ex["input"] for ex in examples] + needles + replacements)
    grammar.addRule(start, x)
    for constant in sorted(c for c in constants if c):
        grammar.addRule(start, solver.mkString(constant))
    pairs = [(n, r) for n in needles for r in replacements if n and n != r]
    for needle, replacement in pairs:
        grammar.addRule(start, solver.mkTerm(Kind.STRING_REPLACE, x, solver.mkString(needle), solver.mkString(replacement)))
        grammar.addRule(start, solver.mkTerm(Kind.STRING_REPLACE_ALL, x, solver.mkString(needle), solver.mkString(replacement)))
    fun = solver.synthFun("rewrite", [x], string_sort, grammar)
    for ex in examples:
        lhs = solver.mkTerm(Kind.APPLY_UF, fun, solver.mkString(ex["input"]))
        rhs = solver.mkString(ex["output"])
        solver.addSygusConstraint(solver.mkTerm(Kind.EQUAL, lhs, rhs))
    result = solver.checkSynth()
    text = str(result)
    if "SOLUTION" in text:
        solution = str(solver.getSynthSolution(fun))
        print(json.dumps({"status": "PROVEN", "stdout": solution, "result": text, "version": getattr(cvc5, "__version__", "unknown"), "modulePath": getattr(cvc5, "__file__", "")}))
    elif "NO_SOLUTION" in text or "no solution" in text.lower():
        print(json.dumps({"status": "UNSAT", "stdout": text, "version": getattr(cvc5, "__version__", "unknown"), "modulePath": getattr(cvc5, "__file__", "")}))
    else:
        print(json.dumps({"status": "UNKNOWN", "stdout": text, "version": getattr(cvc5, "__version__", "unknown"), "modulePath": getattr(cvc5, "__file__", "")}))
except Exception as exc:
    print(json.dumps({"status": "INVALID", "error": repr(exc), "traceback": traceback.format_exc()}))
    sys.exit(3)
`;
  const result = childProcess.spawnSync(pythonBin, ['-c', script], {
    input: JSON.stringify({
      examples,
      candidateNeedles: options.candidateNeedles ?? [],
      candidateReplacements: options.candidateReplacements ?? [],
    }),
    encoding: 'utf8',
    timeout: options.timeoutMs ?? 10_000,
    maxBuffer: 10 * 1024 * 1024,
    env: childEnv(options.env),
  });
  if (result.error) {
    return {
      backend: 'cvc5-sygus',
      verdict: 'UNKNOWN',
      evidence: { ...detected.evidence, reason: result.error.message, stderr: result.stderr ?? '' },
    };
  }
  let parsed: { status?: string; stdout?: string; error?: string; traceback?: string; version?: string; modulePath?: string };
  try {
    parsed = JSON.parse(String(result.stdout ?? '').trim());
  } catch {
    return {
      backend: 'cvc5-sygus',
      verdict: 'UNKNOWN',
      evidence: {
        ...detected.evidence,
        reason: 'cvc5 Python API returned unparseable output',
        stdout: result.stdout ?? '',
        stderr: result.stderr ?? '',
        exitCode: result.status,
        signal: result.signal,
      },
    };
  }
  const verdict = parsed.status === 'PROVEN' ? 'PROVEN' : parsed.status === 'UNSAT' ? 'UNSAT' : parsed.status === 'INVALID' ? 'INVALID' : 'UNKNOWN';
  return {
    backend: 'cvc5-sygus',
    verdict,
    evidence: {
      ...detected.evidence,
      version: parsed.version ?? detected.evidence.version,
      modulePath: parsed.modulePath ?? detected.evidence.modulePath,
      reason: verdict === 'PROVEN' ? 'cvc5 Python API produced a SyGuS solution' : parsed.error ?? 'cvc5 Python API did not prove the SyGuS problem',
      stdout: parsed.stdout ?? '',
      stderr: result.stderr ?? parsed.traceback ?? '',
      exitCode: result.status,
      signal: result.signal,
    },
  };
}

export function runCvc5SyGuS(program: string, options: Cvc5SyGuSOptions = {}): Cvc5Attempt {
  const detected = detectCvc5(options);
  if (detected.verdict === 'ABSENT') return detected;
  if (!options.allowRun) {
    return {
      backend: 'cvc5-sygus',
      verdict: 'UNKNOWN',
      evidence: {
        ...detected.evidence,
        reason: 'cvc5 is reachable, but external solver execution was not requested',
      },
    };
  }

  if (detected.evidence.source === 'python-module') {
    return runPythonCvc5SyGuS(detected, options);
  }

  const bin = detected.evidence.bin;
  if (!bin) return detected;
  const result = childProcess.spawnSync(bin, ['--lang=sygus2'], {
    input: program,
    encoding: 'utf8',
    timeout: options.timeoutMs ?? 10_000,
    maxBuffer: 10 * 1024 * 1024,
    env: childEnv(options.env),
  });

  if (result.error) {
    return {
      backend: 'cvc5-sygus',
      verdict: 'UNKNOWN',
      evidence: {
        ...detected.evidence,
        reason: result.error.message,
        stdout: result.stdout ?? '',
        stderr: result.stderr ?? '',
        exitCode: result.status,
        signal: result.signal,
      },
    };
  }

  if (result.status !== 0) {
    return {
      backend: 'cvc5-sygus',
      verdict: 'UNKNOWN',
      evidence: {
        ...detected.evidence,
        reason: 'cvc5 returned a non-zero status for the SyGuS problem',
        stdout: result.stdout ?? '',
        stderr: result.stderr ?? '',
        exitCode: result.status,
        signal: result.signal,
      },
    };
  }

  const stdout = String(result.stdout ?? '').trim();
  const proved = stdout.length > 0 && !/^unknown\b/i.test(stdout);
  return {
    backend: 'cvc5-sygus',
    verdict: proved ? 'PROVEN' : 'UNKNOWN',
    evidence: {
      ...detected.evidence,
      reason: proved ? 'cvc5 produced a SyGuS solution' : 'cvc5 returned no parseable solution',
      stdout,
      stderr: result.stderr ?? '',
      exitCode: result.status,
      signal: result.signal,
    },
  };
}
