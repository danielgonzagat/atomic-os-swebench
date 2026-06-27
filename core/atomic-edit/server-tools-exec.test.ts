import { describe, expect, it } from 'vitest';
import * as path from 'node:path';
import * as fs from 'node:fs';
import { protectedEffectHits, bubblewrapArgs } from './server-tools-exec.js';
import { REPO_ROOT } from './guard.js';
import {
  findDependencyDirs,
  captureEffectSnapshot,
  rollbackEffect,
  cleanupEffectSnapshot,
} from './server-helpers-effect.js';

describe('server-tools-exec helper functions', () => {
  it('bubblewrapArgs should generate expected sandbox parameters', () => {
    const effectRoot = path.resolve('.');
    const tempRoot = fs.mkdtempSync(path.join(fs.realpathSync(effectRoot), '.tmp-bubblewrap-'));
    try {
      const args = bubblewrapArgs(effectRoot, tempRoot);

      expect(args).toContain('--ro-bind');
      expect(args).toContain('/');
      expect(args).toContain('--unshare-net');
      expect(args).toContain('--bind');
      expect(args).toContain(fs.realpathSync(effectRoot));
      expect(args).toContain(fs.realpathSync(tempRoot));
    } finally {
      fs.rmSync(tempRoot, { recursive: true, force: true });
    }
  });

  it('protectedEffectHits should detect edits to governance-protected files', () => {
    const root = REPO_ROOT;
    const effects = [
      { file: 'CLAUDE.md' },
      { file: 'src/index.ts' },
      { file: 'eslint.config.js' },
    ];
    const hits = protectedEffectHits(root, effects);
    expect(hits.some(h => h.includes('CLAUDE.md'))).toBe(true);
    expect(hits.some(h => h.includes('src/index.ts'))).toBe(false);
  });

  it('should support dependency cloning, rollback, and cleanup', () => {
    const tempDir = fs.mkdtempSync(path.join(REPO_ROOT, '.tmp-dep-test-'));
    const nodeModulesDir = path.join(tempDir, 'node_modules');
    const venvDir = path.join(tempDir, 'venv');
    fs.mkdirSync(nodeModulesDir);
    fs.mkdirSync(venvDir);
    fs.writeFileSync(path.join(nodeModulesDir, 'package.json'), '{}');
    fs.writeFileSync(path.join(venvDir, 'pyvenv.cfg'), '');

    try {
      const found = findDependencyDirs(tempDir);
      expect(found).toContain(nodeModulesDir);
      expect(found).toContain(venvDir);

      const snap = captureEffectSnapshot(tempDir, { cloneDependencies: true });
      expect(snap.dependencyClones).toBeDefined();
      expect(snap.dependencyClones?.length).toBe(2);

      const clonePaths = snap.dependencyClones?.map((c) => c.cloneAbs) ?? [];
      for (const p of clonePaths) {
        expect(fs.existsSync(p)).toBe(true);
      }

      fs.writeFileSync(path.join(nodeModulesDir, 'package.json'), 'modified');
      const dotVenvDir = path.join(tempDir, '.venv');
      fs.mkdirSync(dotVenvDir);
      fs.rmSync(venvDir, { recursive: true, force: true });

      const effects = [
        { file: 'node_modules/package.json', change: 'modified' as const, bytesBefore: 2, bytesAfter: 8 },
        { file: '.venv', change: 'created' as const, bytesBefore: 0, bytesAfter: 0 },
        { file: 'venv', change: 'deleted' as const, bytesBefore: 0, bytesAfter: 0 },
      ];

      const restoredCount = rollbackEffect(snap, effects);
      expect(fs.existsSync(venvDir)).toBe(true);
      expect(fs.existsSync(dotVenvDir)).toBe(false);
      expect(fs.readFileSync(path.join(nodeModulesDir, 'package.json'), 'utf8')).toBe('{}');

      cleanupEffectSnapshot(snap);
      for (const p of clonePaths) {
        expect(fs.existsSync(p)).toBe(false);
      }
    } finally {
      fs.rmSync(tempDir, { recursive: true, force: true });
    }
  });
});
