#!/usr/bin/env node
/**
 * footprint_live_demo.mjs — the LIVE end-to-end realization of proof-footprint confluence
 * (the theorem machine-checked in proof_footprint_z3.py), on REAL files with a REAL recorded
 * read-footprint (not a hand-fed fixture).
 *
 * A footprint tracker = a read accessor that records every locus the verifier touches
 * (the canonical design: Shake `need`, Salsa queries, Bazel declared inputs). The verifier
 * of edit B reads its dependencies THROUGH the tracker; the recorded set becomes B's proof
 * footprint, fed to commute() via EditFact.negativeProof.readLoci. Live discrimination:
 *   - import-closure ALONE calls edit-B and edit-A INDEPENDENT (no import edge);
 *   - the LIVE recorded footprint makes commute() correctly COUPLED, because B's verifier
 *     actually READ the file A edits — a semantic coupling git/CRDT text-overlap AND the
 *     static import graph both MISS. The dormant readLoci surface, made real.
 */
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = process.env.ATOMIC_EDIT_REPO_ROOT
  ?? (() => { let d = path.resolve(here, '..'); for (let i = 0; i < 6; i++) { if (fs.existsSync(path.join(d, 'dist', 'gates', 'algebra.js'))) return d; d = path.resolve(d, '..'); } return path.resolve(here, '..'); })();
const { buildEditFact, commute } = await import(path.join(repoRoot, 'dist', 'gates', 'algebra.js'));

let pass = 0, fail = 0;
const check = (name, cond) => { if (cond) { pass++; console.log('  PASS  ' + name); } else { fail++; console.log('  FAIL  ' + name); } };

// Real fixture: b.ts does NOT import config.json — NO static import edge between them.
const fix = fs.mkdtempSync(path.join(os.tmpdir(), 'atomic-footprint-live-'));
fs.writeFileSync(path.join(fix, 'config.json'), JSON.stringify({ timeoutMs: 5000 }) + '\n');
fs.writeFileSync(path.join(fix, 'b.ts'), 'export function run() { return doWork(); }\nfunction doWork() { return 1; }\n');

// Footprint tracker: a recording read accessor (dependency-injected read capability).
function makeTracker() {
  const recorded = new Set();
  const read = (abs) => {
    const rel = path.relative(fix, path.resolve(abs)).replaceAll('\\', '/');
    if (rel && !rel.startsWith('..')) recorded.add(rel);
    return fs.readFileSync(abs, 'utf8');
  };
  return { read, footprint: () => [...recorded] };
}

// A REAL verifier of b.ts whose correctness depends on the runtime config: to certify b.ts it
// READS config.json (and b.ts itself) THROUGH the tracker — so the footprint is genuinely recorded.
function verifyB(read) {
  const cfg = JSON.parse(read(path.join(fix, 'config.json')));
  read(path.join(fix, 'b.ts'));
  return cfg.timeoutMs > 0; // obligation: the configured timeout bound is positive
}

const tr = makeTracker();
const certified = verifyB(tr.read);
const readLoci = tr.footprint();
check('verifier certified b.ts', certified === true);
check('footprint RECORDED live (not hand-fed) includes config.json', readLoci.includes('config.json'));
check('footprint includes the edited file b.ts (self-read)', readLoci.includes('b.ts'));

// Edit B (to b.ts) carries its LIVE recorded proof footprint.
const editB = buildEditFact(fix, {
  file: 'b.ts',
  modifiedZones: [{ byteStart: 20, byteEnd: 27 }],
  negativeActionProof: { proofSha256: 'ab'.repeat(32), removedByteCount: 3, readLoci },
});
const editA = buildEditFact(fix, { file: 'config.json', modifiedZones: [{ byteStart: 2, byteEnd: 11 }] });

// IMPORT-CLOSURE-ONLY: strip the footprint -> no import edge -> INDEPENDENT (the blind spot).
const editB_importOnly = buildEditFact(fix, { file: 'b.ts', modifiedZones: [{ byteStart: 20, byteEnd: 27 }] });
const vImport = commute(editB_importOnly, editA);
check('import-closure ALONE calls them INDEPENDENT (no import edge) — the blind spot', vImport.commute === true);

// LIVE proof-footprint: commute() uses the recorded readLoci and catches the coupling.
const vLive = commute(editB, editA);
check('LIVE proof-footprint makes commute() COUPLED (catches what imports miss)', vLive.commute === false);
check('coupling reason names the negative-obligation read-locus', /negative-obligation coupling/.test(vLive.reason || '') && vLive.sharedLocus === 'config.json');

fs.rmSync(fix, { recursive: true, force: true });
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
