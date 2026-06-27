#!/usr/bin/env node
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
const json = process.argv.includes('--json');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const failures = [], results = [];
function check(name, condition, detail = {}) { const ok = Boolean(condition); results.push({ name, ok, detail }); if (!ok) failures.push({ name, detail }); if (!json) console.log((ok ? 'PASS ' : 'FAIL ') + name); }
function read(rel) { return fs.readFileSync(path.join(root, rel), 'utf8'); }
for (const rel of ['engine-synthesis-kernel.ts', 'engine-sygus.ts', 'engine-cvc5-sygus.ts', 'engine-theory-ladder.ts', 'engine-meta-synth.ts', 'server-tools-meta-synth.ts']) check('source exists ' + rel, fs.existsSync(path.join(root, rel)));
if (failures.length === 0) {
  const server = read('server.ts'), kernel = read('engine-synthesis-kernel.ts'), meta = read('engine-meta-synth.ts'), sygus = read('engine-sygus.ts'), cvc5 = read('engine-cvc5-sygus.ts'), ladder = read('engine-theory-ladder.ts');
  check('server imports meta-synth tool', server.includes("./server-tools-meta-synth.js"));
  check('server registers atomic_meta_synth registrar', /registerToolsMetaSynth\(server\)/.test(server));
  check('kernel creates proof receipts and verifies hashes', kernel.includes('makeProofReceipt') && kernel.includes('verifyProofReceipt') && kernel.includes('promotionEligible'));
  check('kernel separates heuristic from formal promotion', kernel.includes('HEURISTIC_UNPROVEN') && kernel.includes("authority === 'formal'"));
  check('meta-synth imports SyGuS/kernel/ladder', meta.includes('./engine-sygus.js') && meta.includes('./engine-synthesis-kernel.js') && meta.includes('./engine-theory-ladder.js'));
  check('SyGuS generator emits synth-fun and str.replace', sygus.includes('synth-fun') && sygus.includes('str.replace'));
  check('CVC5 adapter has ABSENT path', /cvc5/i.test(cvc5) && cvc5.includes('ABSENT'));
  check('theory ladder has synthesis levels', ladder.includes('catalog') && ladder.includes('heuristic-cegis') && ladder.includes('cvc5-sygus') && ladder.includes('formal-promotion'));
}
for (const rel of ['dist/engine-synthesis-kernel.js', 'dist/engine-sygus.js', 'dist/engine-cvc5-sygus.js', 'dist/engine-theory-ladder.js', 'dist/engine-meta-synth.js', 'dist/server-tools-meta-synth.js']) check('dist exists ' + rel, fs.existsSync(path.join(root, rel)));
if (failures.length === 0) {
  const kernel = await import(path.join(root, 'dist', 'engine-synthesis-kernel.js'));
  const cvc5 = await import(path.join(root, 'dist', 'engine-cvc5-sygus.js'));
  const meta = await import(path.join(root, 'dist', 'engine-meta-synth.js'));
  const result = meta.synthesizeMetaOperator(meta.DEFAULT_STRING_REPLACE_ISLAND, { allowCvc5: false });
  check('meta-synth result ok for bounded island', result.ok === true, result);
  check('held-out proof passes', result.heldOut?.passed === result.heldOut?.total && result.heldOut?.total >= 4, result.heldOut);
  check('heuristic receipt is not promotion eligible', result.receipts.some((receipt) => receipt.verdict === 'HEURISTIC_UNPROVEN') && result.promotionEligible === false, result.receipts);
  check('receipt hashes verify', result.receipts.every((receipt) => kernel.verifyProofReceipt(receipt).ok), result.receipts);
  check('SyGuS benchmark emitted', result.sygus?.program?.includes('synth-fun') && result.sygus?.program?.includes('str.replace'), result.sygus);
  check('CVC5 absence explicit', cvc5.detectCvc5({ env: { PATH: '' }, candidatePaths: ['/definitely/not/cvc5'], pythonCandidates: [] }).verdict === 'ABSENT');
  check('theory ladder reports no formal promotion', result.ladder?.some((step) => step.level === 'formal-promotion' && step.status === 'blocked'), result.ladder);
  const pythonBin = process.env.CVC5_PYTHON_BIN ?? (fs.existsSync('/opt/homebrew/bin/python3') ? '/opt/homebrew/bin/python3' : undefined);
  if (pythonBin) {
    const formal = meta.synthesizeMetaOperator(meta.DEFAULT_STRING_REPLACE_ISLAND, { allowCvc5: true, pythonBin });
    const cvc5Receipt = formal.receipts.find((receipt) => receipt.backend === 'cvc5-sygus');
    check('python cvc5 proves bounded island when configured', cvc5Receipt?.verdict === 'PROVEN' && cvc5Receipt?.authority === 'formal', cvc5Receipt);
    check('formal cvc5 receipt is promotion eligible', formal.promotionEligible === true, formal.receipts);
    check('theory ladder opens cvc5 and formal promotion levels', formal.ladder?.some((step) => step.level === 'cvc5-sygus' && step.status === 'proved') && formal.ladder?.some((step) => step.level === 'formal-promotion' && step.status === 'proved'), formal.ladder);
  }
}
const output = { ok: failures.length === 0, total: results.length, failed: failures, results };
if (json) console.log(JSON.stringify(output, null, 2)); else console.log(output.ok ? 'OK meta-synth-engine proof' : 'FAIL meta-synth-engine proof');
process.exit(output.ok ? 0 : 1);
