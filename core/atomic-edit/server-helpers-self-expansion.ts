import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
// ── Inter-process self-expansion admission lock (closes the concurrency-corruption defect) ──
// selfExpansionAdmissionDepth below serializes re-entrancy WITHIN a process; it does NOTHING across
// processes, so two concurrent atomic_expand_self runs (e.g. Codex multi-way) both saw depth=1 and
// both wrote the atomic-edit source tree → proof-lattice corruption (proven live: 4-way thrash,
// 42min, zero promote). This lock serializes self-expansion ACROSS processes via an atomic mkdir of
// a lock dir at the (single, canonical) atomic-edit source tree's .atomic/. Acquired ONLY at the
// outermost admission (depth 0→1); the depth counter still handles in-process re-entrancy, so inner
// archive/corpus writes inside one expand_self do NOT re-acquire (no deadlock). A SECOND concurrent
// expand_self fail-fast REFUSES (never corrupts). A crashed holder leaves a stale lock recovered by
// mtime lease (> max expand_self budget). Normal single-process path is identical to before.
const SELF_EXPANSION_LOCK_LEASE_MS = 90 * 60 * 1000; // 90 min > ATOMIC_SELF_EXPANSION_PROOF_GLOBAL_BUDGET_MS (60min)

function selfExpansionLockDir(): string {
  // atomic-edit source root = parent of this compiled module's dir (dist/ -> atomic-edit/). There is
  // exactly ONE atomic-edit source tree per host, and every self-expansion writes THERE regardless of
  // the caller's repoRoot — so one lock guards all of them without needing repoRoot on the signature.
  const moduleDir = path.dirname(fileURLToPath(import.meta.url));
  const atomicEditRoot = path.resolve(moduleDir, '..');
  return path.join(atomicEditRoot, '.atomic', 'self-expansion-admission.lock');
}

function acquireSelfExpansionLock(): void {
  const lockDir = selfExpansionLockDir();
  try { fs.mkdirSync(path.dirname(lockDir), { recursive: true }); } catch { /* parent unwritable → fail-closed below */ }
  try {
    fs.mkdirSync(lockDir); // atomic — throws EEXIST iff held
    try { fs.writeFileSync(path.join(lockDir, 'owner'), `${process.pid}@${Date.now()}`); } catch { /* best-effort */ }
    return; // acquired
  } catch (e) {
    const err = e as NodeJS.ErrnoException;
    if (err.code !== 'EEXIST') throw e; // unexpected (EROFS/ENOENT/...) → fail-closed
    try {
      const st = fs.statSync(lockDir);
      if (Date.now() - st.mtimeMs > SELF_EXPANSION_LOCK_LEASE_MS) {
        fs.rmSync(lockDir, { recursive: true, force: true });
        fs.mkdirSync(lockDir); // re-acquire after steal (a race throws EEXIST → busy, safe)
        try { fs.writeFileSync(path.join(lockDir, 'owner'), `${process.pid}@${Date.now()}`); } catch { /* best-effort */ }
        return;
      }
    } catch { /* stat/rm failed — treat as genuinely held */ }
    throw new Error(
      'refused (self-expansion admission lock): another atomic_expand_self is in progress ' +
        '(inter-process lock held). Concurrent self-expansion corrupts the proof lattice — retry ' +
        'after the in-progress expansion completes or its lease (90m) expires.',
    );
  }
}

function releaseSelfExpansionLock(): void {
  try { fs.rmSync(selfExpansionLockDir(), { recursive: true, force: true }); } catch { /* best-effort */ }
}

let selfExpansionAdmissionDepth = 0;

export function withSelfExpansionAdmission<T>(fn: () => T): T {
  const outermost = selfExpansionAdmissionDepth === 0;
  if (outermost) acquireSelfExpansionLock(); // serialize ACROSS processes (depth counter = in-process re-entrancy)
  selfExpansionAdmissionDepth += 1;
  try {
    return fn();
  } finally {
    selfExpansionAdmissionDepth -= 1;
    if (outermost && selfExpansionAdmissionDepth === 0) releaseSelfExpansionLock();
  }
}

function normalizeRel(rel: string): string {
  return rel.split(path.sep).join('/').replace(/^\.\//, '');
}

function isEphemeralAtomicFixture(rel: string): boolean {
  const base = path.basename(rel);
  return (
    base.startsWith('.smoke-') ||
    base.startsWith('.audit-') ||
    base.startsWith('.atomic-edit.') ||
    rel.includes('/.smoke-') ||
    rel.includes('/.audit-') ||
    rel.includes('/.positive-byte-sessions/') ||
    rel.includes('/dist/') ||
    // Workspace data directories: these live inside the atomic source root
    // but are NOT atomic source code. They are user/benchmark data.
    rel.includes('/.atomic/loop/') ||
    rel.startsWith('.atomic/loop/') ||
    rel.includes('/loop-data/') ||
    rel.startsWith('loop-data/') ||
    rel.startsWith('dist/')
  );
}

/**
 * Detect the atomic-edit source tree itself — the directory holding the
 * running server's `package.json` (name "atomic-edit-mcp"). This is the
 * canonical "self": the atomic-edit code, independent of which workspace
 * the MCP is currently operating on (REPO_ROOT).
 *
 * Closing the self-application gap: an atomic-edit MCP must be able to
 * edit its own source through atomic_expand_self, not just the historical
 * `{repoRoot}/scripts/mcp/atomic-edit/**` layout. Real deployments live at
 * varying paths (here: atomic-os-swebench/core/atomic-edit). Detecting the
 * source root by walking up from this compiled module is location-
 * independent: works under tsx (source) and node (dist).
 *
 * Memoized on first call. Returns null only if the package.json chain is
 * broken — in which case self-expansion falls back to the legacy path-only
 * admission (no regression).
 */
function findRepoRoot(start: string): string {
  let dir = start;
  for (;;) {
    if (fs.existsSync(path.join(dir, '.git'))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) return start;
    dir = parent;
  }
}

let cachedSelfSourceRoot: string | null | undefined;
function atomicEditSourceRoot(): string | null {
  if (cachedSelfSourceRoot !== undefined) return cachedSelfSourceRoot;
  const startDir = path.dirname(fileURLToPath(import.meta.url));
  let dir = startDir;
  for (let i = 0; i < 8; i++) {
    const pj = path.join(dir, 'package.json');
    try {
      if (fs.existsSync(pj)) {
        const j = JSON.parse(fs.readFileSync(pj, 'utf8'));
        // Identity-by-marker, NOT by a drifting package name. The published
        // binary name `atomic-edit-mcp` (the `bin` key) is the stable identity
        // of the atomic-edit source package and survives package renames (the
        // repo-unification renamed `name` to "atomic-os", which silently broke
        // the old name-only check and disabled self-expansion entirely). We
        // still accept the historical/explicit names as a belt-and-suspenders.
        const isAtomicEditPackage =
          (j && (j.name === 'atomic-edit-mcp' || j.name === 'atomic-os')) ||
          (j && j.bin && typeof j.bin === 'object' && Boolean(j.bin['atomic-edit-mcp']));
        if (isAtomicEditPackage) {
          cachedSelfSourceRoot = dir;
          return dir;
        }
      }
    } catch {
      // malformed package.json — keep walking
    }
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }

  // Fallback check relative to repo root
  const repoRoot = findRepoRoot(startDir);
  const candidates = [
    path.join(repoRoot, 'core/atomic-edit'),
    path.join(repoRoot, 'scripts/mcp/atomic-edit'),
  ];
  for (const cand of candidates) {
    const pj = path.join(cand, 'package.json');
    try {
      if (fs.existsSync(pj)) {
        const j = JSON.parse(fs.readFileSync(pj, 'utf8'));
        const isAtomicEditPackage =
          (j && (j.name === 'atomic-edit-mcp' || j.name === 'atomic-os')) ||
          (j && j.bin && typeof j.bin === 'object' && Boolean(j.bin['atomic-edit-mcp']));
        if (isAtomicEditPackage) {
          cachedSelfSourceRoot = cand;
          return cand;
        }
      }
    } catch {
      // ignore
    }
  }

  cachedSelfSourceRoot = null;
  return null;
}


/**
 * Legacy / canonical admission: paths under {repoRoot}/scripts/mcp/atomic-edit/.
 * Still accepted so existing harnesses and tests that mirror the original
 * layout continue to work unchanged.
 */
function admitsUnderLegacyScriptsPath(repoRoot: string, absPath: string): boolean {
  const rel = normalizeRel(path.relative(repoRoot, absPath));
  return rel.startsWith('scripts/mcp/atomic-edit/') && !isEphemeralAtomicFixture(rel);
}

/**
 * Self-application admission: paths under the atomic-edit source tree itself
 * (the running server's package root). Admission is symmetric to the legacy
 * path — same ephemeral-fixture exclusion, same write firewall — just rooted
 * at the real source location. This is what lets the MCP modify its own code
 * from any deployment path.
 */
function admitsUnderSelfSourceRoot(absPath: string): boolean {
  const selfRoot = atomicEditSourceRoot();
  if (!selfRoot) return false;
  const rel = normalizeRel(path.relative(selfRoot, absPath));
  if (!rel || rel.startsWith('..') || path.isAbsolute(rel)) return false;
  return !isEphemeralAtomicFixture(rel);
}

const ATOMIC_AGENT_CLI_SELF_EXPANSION_ROOT_REL = 'core/agent/atomic-full-ab/local-loop';
const ATOMIC_AGENT_CLI_SELF_EXPANSION_SOURCE_FILES = new Set([
  'local_atomic_agent.py',
  'swe_gate.sh',
  'swe_suite_setup.py',
]);

export function atomicAgentCliSelfExpansionRootRel(): string {
  return ATOMIC_AGENT_CLI_SELF_EXPANSION_ROOT_REL;
}

export function atomicAgentCliSelfExpansionSourceRelPaths(): string[] {
  return Array.from(
    ATOMIC_AGENT_CLI_SELF_EXPANSION_SOURCE_FILES,
    (file) => ATOMIC_AGENT_CLI_SELF_EXPANSION_ROOT_REL + '/' + file,
  );
}

export function isAtomicAgentCliSelfExpansionPath(repoRoot: string, absPath: string): boolean {
  const rel = normalizeRel(path.relative(repoRoot, absPath));
  const prefix = ATOMIC_AGENT_CLI_SELF_EXPANSION_ROOT_REL + '/';
  if (!rel.startsWith(prefix)) return false;
  const rest = rel.slice(prefix.length);
  if (!rest || rest.includes('/')) return false;
  return ATOMIC_AGENT_CLI_SELF_EXPANSION_SOURCE_FILES.has(rest);
}

export function isAtomicSelfExpansionPath(repoRoot: string, absPath: string): boolean {
  return admitsUnderLegacyScriptsPath(repoRoot, absPath) || admitsUnderSelfSourceRoot(absPath) || isAtomicAgentCliSelfExpansionPath(repoRoot, absPath);
}

export function atomicSelfSourceRoot(): string {
  return atomicEditSourceRoot() ?? '.';
}

export function assertSelfExpansionAdmission(repoRoot: string, absPath: string, nextContent: string): void {
  if (!isAtomicSelfExpansionPath(repoRoot, absPath)) return;
  let before: string | null = null;
  try {
    before = fs.existsSync(absPath) && fs.statSync(absPath).isFile() ? fs.readFileSync(absPath, 'utf8') : null;
  } catch {
    before = null;
  }
  if (before === nextContent) return;
  if (selfExpansionAdmissionDepth > 0) return;
  const rel = normalizeRel(path.relative(repoRoot, absPath));
  throw new Error(
    `refused (self-expansion admission): ${rel} is part of atomic-edit itself. ` +
      `Expanding the atomic MCP is allowed only through atomic_expand_self, which wraps the write in ` +
      `self-expansion admission and requires proof commands before the expansion can stand. ` +
      `Use atomic_expand_self to execute the closed loop: atomic executes the computation, or atomic first ` +
      `implements the missing computation inside atomic under proof.`,
  );
}

