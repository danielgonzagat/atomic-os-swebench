#!/usr/bin/env node
/**
 * edit-quality-bench.mjs — N4: the edit-QUALITY A/B (the dimension where atomic actually plays).
 *
 * SWE-bench measures task RESOLUTION (Pass@1); there atomic shows no edge (see AB-FINDING.md).
 * atomic's real, distinct claim is EDIT SAFETY: it validates syntax PRE-DISK and refuses to write a
 * broken state — so a syntactically-invalid edit NEVER reaches disk. This benchmark measures exactly
 * that, honestly, with the same model proposals applied two ways:
 *
 *   ATOMIC arm — apply via the governed engine (atomic-call atomic_replace_text): validates the
 *                resulting file with a REAL parser before writing; refuses (ok:false) if invalid.
 *   RAW arm    — naive textual apply (string replace + write), like a textual patch / sed: no check.
 *
 * Ground truth: after each apply, the resulting file is independently parsed (python3 ast.parse for
 * .py). Metrics per arm over N proposals:
 *   - applied:           edit found its target and was written
 *   - invalidOnDisk:     a SYNTACTICALLY BROKEN file was written (atomic must be 0 by construction)
 *   - validApplied:      applied AND result parses
 *   - meanDiffBytes:     average |new|-|old| magnitude
 * The honest edge is invalidOnDisk: atomic=0 guaranteed; raw>0 whenever the model proposes a broken edit.
 * If the model never errs on the set, both are 0 — an honest null (atomic is insurance that didn't bind).
 *
 * This is NOT rigged: it uses the model's REAL proposals; the only variable is the apply mechanism.
 * To make the guarantee BIND (show the tail), tasks include edits that are easy to get syntactically
 * wrong (byte-removing, multi-line, indentation-sensitive) — the realistic catastrophic case.
 *
 * Usage: DEEPSEEK_API_KEY=... node edit-quality-bench.mjs [--n 12] [--model deepseek-v4-pro]
 * Output: a JSON report to stdout + edit-quality-result.json.
 */
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { spawnSync } from 'node:child_process';
import https from 'node:https';

const API_KEY = process.env.DEEPSEEK_API_KEY || '';
const MODEL = (process.argv.includes('--model') ? process.argv[process.argv.indexOf('--model') + 1] : 'deepseek-v4-pro');
const ATOMIC = path.resolve(process.env.ATOMIC_EDIT_SRC || path.join(path.dirname(new URL(import.meta.url).pathname), '..', '..', 'atomic-edit'));
const CALL = path.join(ATOMIC, 'atomic-call.mjs');

// Edit tasks at the model's syntactic error edge — indentation/multiline/byte-removing transforms.
const TASKS = [
  { lang: 'py', file: 'm.py',
    src: 'def total(items):\n    s = 0\n    for it in items:\n        s += it.price\n    return s\n',
    instr: 'Rewrite total() to use sum() with a generator expression over it.price, keeping the same behavior.' },
  { lang: 'py', file: 'm.py',
    src: 'def parse(line):\n    parts = line.split(",")\n    name = parts[0]\n    age = int(parts[1])\n    return {"name": name, "age": age}\n',
    instr: 'Wrap the body of parse() in a try/except ValueError that returns None on bad input. Keep the happy path identical.' },
  { lang: 'py', file: 'm.py',
    src: 'class Cache:\n    def __init__(self):\n        self.d = {}\n    def get(self, k):\n        return self.d[k]\n',
    instr: 'Change get() to return self.d.get(k, None) and add a set(self, k, v) method that stores v under k.' },
  { lang: 'py', file: 'm.py',
    src: 'def fib(n):\n    if n < 2:\n        return n\n    return fib(n-1) + fib(n-2)\n',
    instr: 'Convert fib() to an iterative version using a loop (no recursion), same result.' },
  { lang: 'py', file: 'm.py',
    src: 'def fmt(rows):\n    out = []\n    for r in rows:\n        out.append("%s=%s" % (r[0], r[1]))\n    return "; ".join(out)\n',
    instr: 'Rewrite fmt() as a single return with a list comprehension and f-strings.' },
  { lang: 'py', file: 'm.py',
    src: 'def clamp(x, lo, hi):\n    if x < lo:\n        return lo\n    elif x > hi:\n        return hi\n    else:\n        return x\n',
    instr: 'Collapse clamp() to a single line: return max(lo, min(x, hi)).' },
];

function deepseek(prompt) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({ model: MODEL, temperature: 0, max_tokens: 1500,
      messages: [{ role: 'user', content: prompt }] });
    const req = https.request('https://api.deepseek.com/v1/chat/completions',
      { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${API_KEY}`, 'Content-Length': Buffer.byteLength(body) } },
      (res) => { let d = ''; res.on('data', (c) => (d += c)); res.on('end', () => { try { resolve(JSON.parse(d).choices[0].message.content); } catch (e) { reject(e); } }); });
    req.on('error', reject); req.write(body); req.end();
  });
}

function pyValid(file) {
  const r = spawnSync('python3', ['-c', `import ast,sys; ast.parse(open(${JSON.stringify(file)}).read())`], { encoding: 'utf8' });
  return r.status === 0;
}

// ask the model for a single verbatim oldText->newText edit
async function proposeEdit(task) {
  const p = `You are editing a ${task.lang} file. Here is the FULL file:\n\n${task.src}\n\nTASK: ${task.instr}\n\nReturn ONLY a JSON object {"oldText": "...", "newText": "..."} where oldText is an EXACT verbatim substring of the file to replace and newText is the replacement. The oldText must appear exactly once. No prose, no fences.`;
  const raw = await deepseek(p);
  const m = raw.match(/\{[\s\S]*\}/);
  if (!m) return null;
  try { const o = JSON.parse(m[0]); if (typeof o.oldText === 'string' && typeof o.newText === 'string') return o; } catch { /* */ }
  return null;
}

function atomicApply(file, oldText, newText) {
  const ws = path.dirname(file);
  const before = fs.readFileSync(file, 'utf8');
  const args = JSON.stringify({ file, oldText, newText, proofOfIncorrectness: 'edit-quality benchmark: applying the model-proposed transformation; removed/changed bytes are the prior implementation being replaced per the task instruction.' });
  spawnSync(process.execPath, [CALL, 'atomic_replace_text', args],
    { encoding: 'utf8', env: { ...process.env, ATOMIC_WORKSPACE_ROOT: ws, ATOMIC_EDIT_ALLOWED_ROOTS: ws, ATOMIC_DISABLE_HOT_RELOAD: '1' } });
  // ground-truth success = the engine actually WROTE a change (it refuses by leaving the file untouched).
  // atomic-call renders human-readable output, not a JSON ok-line, so detect by the file itself.
  return fs.readFileSync(file, 'utf8') !== before;
}

function rawApply(file, oldText, newText) {
  const cur = fs.readFileSync(file, 'utf8');
  if (!cur.includes(oldText)) return false;
  fs.writeFileSync(file, cur.replace(oldText, newText));
  return true;
}

async function run() {
  if (!API_KEY) { console.error('DEEPSEEK_API_KEY required'); process.exit(2); }
  const n = process.argv.includes('--n') ? Number(process.argv[process.argv.indexOf('--n') + 1]) : TASKS.length;
  const arms = { atomic: { applied: 0, invalidOnDisk: 0, validApplied: 0, diffs: [] }, raw: { applied: 0, invalidOnDisk: 0, validApplied: 0, diffs: [] } };
  const rows = [];
  for (let i = 0; i < n; i++) {
    const task = TASKS[i % TASKS.length];
    const edit = await proposeEdit(task);
    if (!edit) { rows.push({ i, proposed: false }); continue; }
    const diffBytes = Math.abs(Buffer.byteLength(edit.newText) - Buffer.byteLength(edit.oldText));
    for (const arm of ['atomic', 'raw']) {
      const dir = fs.mkdtempSync(path.join(os.tmpdir(), `eqb-${arm}-`));
      const file = path.join(dir, task.file);
      fs.writeFileSync(file, task.src);
      const applied = arm === 'atomic' ? atomicApply(file, edit.oldText, edit.newText) : rawApply(file, edit.oldText, edit.newText);
      const valid = task.lang === 'py' ? pyValid(file) : true;
      if (applied) arms[arm].applied++;
      // invalid-on-disk = the file on disk is broken (only possible if something was written)
      const changed = fs.readFileSync(file, 'utf8') !== task.src;
      if (changed && !valid) arms[arm].invalidOnDisk++;
      if (applied && valid) { arms[arm].validApplied++; arms[arm].diffs.push(diffBytes); }
      rows.push({ i, arm, applied, valid, changed });
      fs.rmSync(dir, { recursive: true, force: true });
    }
  }
  const mean = (a) => (a.length ? Math.round(a.reduce((x, y) => x + y, 0) / a.length) : 0);
  const report = {
    model: MODEL, n,
    atomic: { ...arms.atomic, meanDiffBytes: mean(arms.atomic.diffs), diffs: undefined },
    raw: { ...arms.raw, meanDiffBytes: mean(arms.raw.diffs), diffs: undefined },
    verdict:
      arms.raw.invalidOnDisk > arms.atomic.invalidOnDisk
        ? `ATOMIC EDGE BOUND: atomic wrote ${arms.atomic.invalidOnDisk} broken files, raw wrote ${arms.raw.invalidOnDisk}. atomic's pre-disk guarantee prevented ${arms.raw.invalidOnDisk - arms.atomic.invalidOnDisk} catastrophic edit(s).`
        : `NULL on this set: raw invalidOnDisk=${arms.raw.invalidOnDisk}, atomic=${arms.atomic.invalidOnDisk}. The model did not propose a broken edit here, so atomic's guarantee did not bind. atomic is insurance; on a strong model + small edits the premium rarely pays out. Needs larger N / weaker model / bigger edits to bind.`,
  };
  console.log(JSON.stringify(report, null, 2));
  fs.writeFileSync(path.join(path.dirname(new URL(import.meta.url).pathname), 'edit-quality-result.json'), JSON.stringify(report, null, 2));
}
run().catch((e) => { console.error('edit-quality-bench failed:', e); process.exit(1); });
