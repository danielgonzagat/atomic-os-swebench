import * as childProcess from 'node:child_process';
import * as fs from 'node:fs';
import type { SynthesisVerdict } from './engine-synthesis-kernel.js';

export interface Cvc5DetectionOptions {
  cvc5Bin?: string;
  candidatePaths?: string[];
  env?: NodeJS.ProcessEnv;
  timeoutMs?: number;
}

export interface Cvc5Attempt {
  backend: 'cvc5-sygus';
  verdict: Extract<SynthesisVerdict, 'PROVEN' | 'UNKNOWN' | 'ABSENT' | 'INVALID'>;
  evidence: {
    checked: string[];
    bin: string | null;
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
}

const DEFAULT_CVC5_PATHS = ['/opt/homebrew/bin/cvc5', '/usr/local/bin/cvc5', '/usr/bin/cvc5'];

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

function pathCandidates(env: NodeJS.ProcessEnv): string[] {
  return String(env.PATH ?? '')
    .split(':')
    .filter(Boolean)
    .map((entry) => `${entry.replace(/\/+$/, '')}/cvc5`);
}

export function detectCvc5(options: Cvc5DetectionOptions = {}): Cvc5Attempt {
  const env = options.env ?? process.env;
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
        checked,
        bin,
        reason: 'cvc5 executable detected; no SyGuS proof has been run yet',
        version: String(version.stdout || version.stderr || '').trim(),
        exitCode: version.status,
        signal: version.signal,
      },
    };
  }

  return {
    backend: 'cvc5-sygus',
    verdict: 'ABSENT',
    evidence: {
      checked,
      bin: null,
      reason: 'cvc5 binary not found; set CVC5_BIN or provide cvc5Bin to enable SyGuS solving',
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

  const bin = detected.evidence.bin;
  if (!bin) return detected;
  const result = childProcess.spawnSync(bin, ['--lang=sygus2'], {
    input: program,
    encoding: 'utf8',
    timeout: options.timeoutMs ?? 10_000,
    maxBuffer: 10 * 1024 * 1024,
    env: options.env ?? process.env,
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
