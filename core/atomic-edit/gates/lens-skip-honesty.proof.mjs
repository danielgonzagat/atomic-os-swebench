/**
 * lens-skip-honesty.proof.mjs -- proves the source-language lens is HONEST about coverage:
 * it exposes direct code-like files skipped by the source gates and ignores generated scratch
 * directories instead of reporting proof/runtime litter as product source.
 * Run: node gates/lens-skip-honesty.proof.mjs
 */
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { runLens } from '../dist/gates/lens.js';
import { enumerateSkipped } from '../dist/server-tools-lens.js';

let pass = 0;
let fail = 0;

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'atomic-lens-skip-'));
fs.writeFileSync(path.join(tmp, 'foo.ts'), 'export const x = 1;\n');
fs.writeFileSync(path.join(tmp, 'a.css'), '.a{color:red}\n');
fs.writeFileSync(path.join(tmp, 'q.sql'), 'SELECT 1;\n');
fs.writeFileSync(path.join(tmp, 'page.html'), '<div></div>\n');
fs.writeFileSync(path.join(tmp, 'go.sh'), 'echo hi\n');
fs.writeFileSync(path.join(tmp, 'README.md'), '# prose\n');

for (const dir of ['.planning/references', 'atomic-type-gate-123', 'atomic-edit-dist-123', 'dist-lkg.tmp-123', '.external-runtime-denial-123', '0123456789abcdef0123456789abcdef']) {
  fs.mkdirSync(path.join(tmp, dir), { recursive: true });
  fs.writeFileSync(path.join(tmp, dir, 'generated.ts'), 'export const generated = true;\n');
}

const skipped = enumerateSkipped(tmp, '.');
const single = enumerateSkipped(tmp, 'a.css');
const tsOnly = enumerateSkipped(tmp, 'foo.ts');
const generatedOnly = enumerateSkipped(tmp, 'atomic-type-gate-123');
const distLkgTmpOnly = enumerateSkipped(tmp, 'dist-lkg.tmp-123');
const planningLens = await runLens(tmp, '.planning');
const generatedLens = await runLens(tmp, 'atomic-type-gate-123');
const distLkgTmpLens = await runLens(tmp, 'dist-lkg.tmp-123');

const checks = [
  { name: 'counts the 4 source-lens-skipped direct code files (css/sql/html/sh)', cond: skipped.length === 4, detail: skipped },
  { name: 'does NOT count the .ts source file', cond: !skipped.some((f) => f.endsWith('.ts')), detail: skipped },
  { name: 'does NOT count generated scratch source files', cond: !skipped.some((f) => f.includes('generated.ts')), detail: skipped },
  { name: 'does NOT count prose markdown as source-lens skipped code', cond: !skipped.includes('README.md'), detail: skipped },
  { name: 'lists the css/sql/html/sh files', cond: ['a.css', 'q.sql', 'page.html', 'go.sh'].every((f) => skipped.includes(f)), detail: skipped },
  { name: 'single .css scope is honest: skipped 1 (explicit, not silent)', cond: single.length === 1 && single[0] === 'a.css', detail: single },
  { name: 'a TS-only scope has 0 skipped', cond: tsOnly.length === 0, detail: tsOnly },
  { name: 'generated scratch scope has 0 skipped files', cond: generatedOnly.length === 0, detail: generatedOnly },
  { name: 'dist-lkg tmp scope has 0 skipped files', cond: distLkgTmpOnly.length === 0, detail: distLkgTmpOnly },
  { name: 'runLens scans 0 files under .planning generated material', cond: planningLens.scanned === 0, detail: planningLens },
  { name: 'runLens scans 0 files under generated proof scratch', cond: generatedLens.scanned === 0, detail: generatedLens },
  { name: 'runLens scans 0 files under dist-lkg tmp generated material', cond: distLkgTmpLens.scanned === 0, detail: distLkgTmpLens },
];

for (const item of checks) {
  if (item.cond) {
    pass += 1;
  } else {
    fail += 1;
    console.log('FAIL:', item.name, item.detail ?? '');
  }
}

fs.rmSync(tmp, { recursive: true, force: true });
console.log(`\nLENS-SKIP-HONESTY ${pass}/${pass + fail}`);
if (fail) process.exit(1);
