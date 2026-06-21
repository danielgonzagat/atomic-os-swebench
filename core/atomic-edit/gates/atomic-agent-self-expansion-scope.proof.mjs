#!/usr/bin/env node
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
const jsonMode = process.argv.includes('--json');
const sourceDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const helper = fs.readFileSync(path.join(sourceDir, 'server-helpers-self-expansion.ts'), 'utf8');
const selfTools = fs.readFileSync(path.join(sourceDir, 'server-tools-self.ts'), 'utf8');
const effect = fs.readFileSync(path.join(sourceDir, 'server-helpers-effect.ts'), 'utf8');
const results = [];
function record(name, ok, detail = {}) { results.push({ name, ok: Boolean(ok), detail }); }
record('admission exposes the canonical Atomic Agent CLI local-loop root as a named self-expansion root', helper.includes("const ATOMIC_AGENT_CLI_SELF_EXPANSION_ROOT_REL = 'core/agent/atomic-full-ab/local-loop'") && helper.includes('export function atomicAgentCliSelfExpansionRootRel()'));
record('admission allows only top-level Atomic Agent CLI source files, not nested task or evidence data', helper.includes('ATOMIC_AGENT_CLI_SELF_EXPANSION_SOURCE_FILES') && helper.includes("'local_atomic_agent.py'") && helper.includes("'swe_gate.sh'") && helper.includes("'swe_suite_setup.py'") && helper.includes("rest.includes('/')") && helper.includes('ATOMIC_AGENT_CLI_SELF_EXPANSION_SOURCE_FILES.has(rest)'));
record('atomic self-expansion path predicate includes the agent CLI source root but keeps the legacy/self roots intact', helper.includes('admitsUnderLegacyScriptsPath(repoRoot, absPath) || admitsUnderSelfSourceRoot(absPath) || isAtomicAgentCliSelfExpansionPath(repoRoot, absPath)'));
record('self-expansion snapshots only admitted Atomic Agent CLI source files, not loop ledgers/evidence/tasks', helper.includes('export function atomicAgentCliSelfExpansionSourceRelPaths()') && helper.includes("ATOMIC_AGENT_CLI_SELF_EXPANSION_ROOT_REL + '/' + file") && selfTools.includes('interface SelfExpansionSnapshotBundle extends EffectSnapshot') && selfTools.includes('agentCli: EffectSnapshot | null') && selfTools.includes('selfExpansionTouchesAtomicAgentCli') && selfTools.includes('isAtomicAgentCliSelfExpansionPath(REPO_ROOT, absPath)') && selfTools.includes('includeRel: atomicAgentCliSelfExpansionSourceRelPaths()') && !selfTools.includes('includeRel: [atomicAgentCliSelfExpansionRootRel()]'));
record('self-expansion diffs and strict rollback cover both the atomic-edit primary snapshot and the agent CLI snapshot', selfTools.includes('function diffSelfExpansionSnapshot') && selfTools.includes('const primary = diffEffect(snap.primary)') && selfTools.includes('const agentCli = snap.agentCli ? diffEffect(snap.agentCli) : []') && selfTools.includes('function rollbackSelfExpansionSnapshotStrict') && selfTools.includes("rollbackEffectStrict(snap.agentCli, effects.agentCli, action + ':agent-cli')") && selfTools.includes('rollbackEffectStrict(snap.primary, effects.primary, action)'));
record('atomic_expand_self success and rejection paths use the multi-root diff/rollback envelope', selfTools.includes('const snap = captureSelfExpansionSnapshot(selfRoot, ops)') && !selfTools.includes('const effectsBeforePromotion = diffEffect(snap);') && selfTools.includes('const effectsBeforePromotion = diffSelfExpansionSnapshot(snap)') && selfTools.includes('assertNoUnexpectedSelfExpansionEffects(effectsBeforePromotion.effects, applied)') && selfTools.includes('rollbackSelfExpansionSnapshotStrict(snap, effectsBeforeRejectRollback,') && selfTools.includes('limitReached: selfExpansionSnapshotLimitReached(snap)') && selfTools.includes('files: effects.effects'));
record('effect snapshots skip Python bytecode caches so local-loop monitoring remains text byte-exact', effect.includes("'__pycache__'") && effect.includes('const SKIP_DIRS = new Set'));
record('self-expansion validator lattice permanently runs this scope proof', selfTools.includes("{ phase: 'agent-driver-self-scope', command: 'node gates/atomic-agent-self-expansion-scope.proof.mjs --json' }"));
const ok = results.every((entry) => entry.ok);
if (jsonMode) console.log(JSON.stringify({ ok, results }, null, 2));
else for (const entry of results) console.log((entry.ok ? 'PASS' : 'FAIL') + ' ' + entry.name);
process.exit(ok ? 0 : 1);
