#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const root = process.cwd();
const sourcePath = path.join(root, 'server-tools-self.ts');
const source = fs.readFileSync(sourcePath, 'utf8');

const checks = [
  {
    id: 'abort-rollback-helper',
    ok: source.includes('function installSelfExpansionAbortRollback'),
  },
  {
    id: 'exit-handler',
    ok: source.includes("process.once('exit', onExit)"),
  },
  {
    id: 'sigterm-handler',
    ok: source.includes("process.once('SIGTERM', onSigterm)"),
  },
  {
    id: 'strict-rollback',
    ok: source.includes('rollbackSelfExpansionSnapshotStrict(snap, effects, `atomic_expand_self:abort:${reason}`)'),
  },
  {
    id: 'armed-after-write',
    ok: /const applied = withSelfExpansionAdmission\([\s\S]*?abortRollback = installSelfExpansionAbortRollback\(snap\);/.test(source),
  },
  {
    id: 'disarm-after-explicit-rollback',
    ok: (source.match(/abortRollback\.disarm\(\);/g) ?? []).length >= 3,
  },
  {
    id: 'registered-mandatory-validator',
    ok: source.includes("node gates/self-expansion-abort-rollback.proof.mjs --json"),
  },
];

const failed = checks.filter((check) => !check.ok);
const result = {
  ok: failed.length === 0,
  gate: 'self-expansion-abort-rollback',
  checks,
};

if (process.argv.includes('--json')) {
  process.stdout.write(`${JSON.stringify(result)}\n`);
} else if (result.ok) {
  process.stdout.write('self-expansion abort rollback proof passed\n');
} else {
  process.stderr.write(`self-expansion abort rollback proof failed: ${failed.map((check) => check.id).join(', ')}\n`);
}

process.exit(result.ok ? 0 : 1);
