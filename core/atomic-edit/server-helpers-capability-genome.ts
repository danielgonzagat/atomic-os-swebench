import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { readLessonLedger, verifyLessonLedgerChain } from './server-helpers-lesson-ledger.js';
import { computeMapElitesMetrics, getMapElitesArchive } from './server-helpers-qd.js';

export type CapabilityDomain = 'code-editing' | 'self-evolution' | 'memory' | 'immune' | 'discovery' | 'runtime' | 'governance' | 'unknown';
export type CapabilityStatus = 'promoted' | 'mixed' | 'rejected' | 'unproven';

export interface CapabilityEvidenceReceipt {
  kind: string;
  source: string;
  sha256?: string;
  count?: number;
  detail?: Record<string, unknown>;
}

export interface CapabilityGenome {
  id: string;
  toolName: string;
  domain: CapabilityDomain;
  status: CapabilityStatus;
  purpose: string;
  preconditions: string[];
  risks: string[];
  requiredProofs: string[];
  counterProofs: string[];
  sourceFiles: string[];
  evidenceReceipts: CapabilityEvidenceReceipt[];
  history: Record<string, unknown>;
  fitness: Record<string, unknown>;
  lineage: Record<string, unknown>;
  proofLimits: string[];
}

export interface SelfEvolutionArchiveSummary {
  path: string;
  exists: boolean;
  sourceSha256: string | null;
  totalLines: number;
  jsonEntries: number;
  counterExamples: number;
  invalidLines: number;
  promoteCount: number;
  rejectCount: number;
  latestDecision: string | null;
  latestReceiptSha256: string | null;
  latestArchiveEntrySha256: string | null;
  latestParentId: string | null;
  latestCandidateId: string | null;
  requiredGateCount: number;
  requiredGateSample: string[];
}

export interface CapabilityGenomeRegistry {
  kind: 'atomic-capability-genome-registry';
  schemaVersion: 1;
  generatedAt: string;
  repoRoot: string;
  sourceDigest: string;
  capabilities: CapabilityGenome[];
  evidence: {
    toolsDiscovered: number;
    sourceFilesScanned: Array<{ path: string; sha256: string }>;
    selfEvolutionArchive: SelfEvolutionArchiveSummary;
    lessonLedger: { records: number; accepted: number; rejected: number; chainOk: boolean; error?: string };
    qdArchive: { cells: number; averageFitness: number };
  };
  invariants: string[];
  proofLimits: string[];
}

export interface CapabilityGenomeVerification {
  ok: boolean;
  failures: string[];
  warnings: string[];
}

interface DiscoveredTool {
  name: string;
  sourceFiles: string[];
  sourceSha256s: string[];
}

function sha256(value: string): string {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function stableValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(stableValue);
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(Object.entries(value as Record<string, unknown>).sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => [k, stableValue(v)]));
}

function stableJson(value: unknown): string {
  return JSON.stringify(stableValue(value));
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function stringValue(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((entry): entry is string => typeof entry === 'string') : [];
}

function relPath(repoRoot: string, file: string): string {
  return path.relative(repoRoot, file).split(path.sep).join('/');
}

function readTextIfFile(file: string): { text: string; sha256: string } | null {
  try {
    if (!fs.statSync(file).isFile()) return null;
    const text = fs.readFileSync(file, 'utf8');
    return { text, sha256: sha256(text) };
  } catch {
    return null;
  }
}

function candidateToolFiles(repoRoot: string): string[] {
  try {
    return fs.readdirSync(repoRoot).filter((name) => /^server-tools.*\.ts$/.test(name)).map((name) => path.join(repoRoot, name)).sort();
  } catch {
    return [];
  }
}

export function discoverMcpTools(repoRoot: string): { tools: DiscoveredTool[]; sourceFiles: Array<{ path: string; sha256: string }> } {
  const sourceFiles: Array<{ path: string; sha256: string }> = [];
  const toolsByName = new Map<string, DiscoveredTool>();
  const toolCallPattern = /\bserver\.(?:registerTool|tool)\(\s*(['"`])([^'"`]+)\1/g;

  for (const file of candidateToolFiles(repoRoot)) {
    const source = readTextIfFile(file);
    if (!source) continue;
    const relative = relPath(repoRoot, file);
    sourceFiles.push({ path: relative, sha256: source.sha256 });
    for (const match of source.text.matchAll(toolCallPattern)) {
      const name = match[2];
      if (!name) continue;
      const existing = toolsByName.get(name) ?? { name, sourceFiles: [], sourceSha256s: [] };
      existing.sourceFiles.push(relative);
      existing.sourceSha256s.push(source.sha256);
      toolsByName.set(name, existing);
    }
  }

  return { tools: Array.from(toolsByName.values()).sort((a, b) => a.name.localeCompare(b.name)), sourceFiles };
}

export function summarizeSelfEvolutionArchive(repoRoot: string): SelfEvolutionArchiveSummary {
  const archivePath = path.join(repoRoot, 'self-evolution-archive.jsonl');
  const summary: SelfEvolutionArchiveSummary = {
    path: relPath(repoRoot, archivePath),
    exists: false,
    sourceSha256: null,
    totalLines: 0,
    jsonEntries: 0,
    counterExamples: 0,
    invalidLines: 0,
    promoteCount: 0,
    rejectCount: 0,
    latestDecision: null,
    latestReceiptSha256: null,
    latestArchiveEntrySha256: null,
    latestParentId: null,
    latestCandidateId: null,
    requiredGateCount: 0,
    requiredGateSample: [],
  };
  const source = readTextIfFile(archivePath);
  if (!source) return summary;
  summary.exists = true;
  summary.sourceSha256 = source.sha256;

  for (const rawLine of source.text.split('\n')) {
    const line = rawLine.trim();
    if (!line) continue;
    summary.totalLines += 1;
    if (line.startsWith('CONTRA-EXEMPLO')) {
      summary.counterExamples += 1;
      continue;
    }
    if (!line.startsWith('{')) {
      summary.invalidLines += 1;
      continue;
    }
    try {
      const parsed: unknown = JSON.parse(line);
      if (!isRecord(parsed)) {
        summary.invalidLines += 1;
        continue;
      }
      const receipt = isRecord(parsed.receipt) ? parsed.receipt : undefined;
      const decision = stringValue(parsed.decision) ?? stringValue(receipt?.decision);
      summary.jsonEntries += 1;
      if (decision === 'promote') summary.promoteCount += 1;
      if (decision === 'reject') summary.rejectCount += 1;
      summary.latestDecision = decision ?? summary.latestDecision;
      summary.latestReceiptSha256 = stringValue(parsed.receiptSha256) ?? stringValue(receipt?.receiptSha256) ?? summary.latestReceiptSha256;
      summary.latestArchiveEntrySha256 = stringValue(parsed.archiveEntrySha256) ?? summary.latestArchiveEntrySha256;
      summary.latestParentId = stringValue(parsed.parentId) ?? stringValue(receipt?.parentId) ?? summary.latestParentId;
      summary.latestCandidateId = stringValue(parsed.candidateId) ?? stringValue(receipt?.candidateId) ?? summary.latestCandidateId;
      const policy = isRecord(receipt?.policy) ? receipt.policy : undefined;
      const requiredGates = stringArray(policy?.requiredGates);
      if (requiredGates.length > 0) {
        summary.requiredGateCount = Math.max(summary.requiredGateCount, requiredGates.length);
        summary.requiredGateSample = requiredGates.slice(0, 12);
      }
    } catch {
      summary.invalidLines += 1;
    }
  }
  return summary;
}

function domainForTool(name: string): CapabilityDomain {
  if (name === 'atomic_expand_self' || name === 'atomic_self_evolution') return 'self-evolution';
  if (name.startsWith('atomic_lesson') || name.includes('memory')) return 'memory';
  if (name.includes('disproof') || name.includes('shadow')) return 'immune';
  if (name.includes('qd') || name.includes('generator_nonllm') || name.includes('affected_tests')) return 'discovery';
  if (name.includes('exec') || name.includes('shell') || name.includes('chrome') || name.includes('browser')) return 'runtime';
  if (name.includes('certificate') || name.includes('health') || name.includes('proof') || name.includes('config')) return 'governance';
  if (name.startsWith('atomic_') || name.startsWith('code_') || name.includes('rename') || name.includes('import')) return 'code-editing';
  return 'unknown';
}

function purposeForTool(name: string, domain: CapabilityDomain): string {
  if (name === 'atomic_expand_self') return 'Admit or reject Atomic self-expansion candidates under mandatory validator lattice, rollback, proof receipts, disproof briefing, and lesson recording.';
  if (name === 'atomic_self_evolution') return 'Evaluate deterministic self-evolution decisions, promotion receipts, archive entries, archive-chain verification, and receipt forgery rejection.';
  if (name.startsWith('atomic_lesson')) return 'Record, query, or verify procedural memory from effect-indexed lessons with provenance.';
  if (name.includes('qd') || name.includes('generator_nonllm')) return 'Search for non-LLM variants and maintain quality-diversity fitness evidence for discovered repair patterns.';
  if (name.includes('disproof') || name.includes('shadow')) return 'Select counterexamples, brief known walls, and falsify proposals before capability promotion.';
  if (name.includes('exec')) return 'Run external commands through Atomic runtime policy, sandboxing, receipts, and effect metadata.';
  if (name.includes('health') || name.includes('certificate')) return 'Expose certificate and health state so autonomy can be gated by proof status.';
  return `Expose the ${domain} capability named ${name} through the Atomic MCP action surface.`;
}

function preconditionsForDomain(domain: CapabilityDomain): string[] {
  const common = ['tool is registered in the Atomic MCP server', 'source file hash is included in the capability registry'];
  if (domain === 'self-evolution') return [...common, 'parent/candidate/policy facts are explicit', 'mandatory validator lattice is not bypassed'];
  if (domain === 'memory') return [...common, 'lesson records preserve a hash chain', 'memory entries carry effect evidence'];
  if (domain === 'immune') return [...common, 'counterexample corpus verifies before selection', 'briefing is treated as guidance, not proof'];
  if (domain === 'discovery') return [...common, 'candidate fitness is computed from recorded effects', 'novelty does not override gates'];
  if (domain === 'runtime') return [...common, 'runtime action has declared command class and sandbox mode', 'effects are observable or explicitly read-only'];
  if (domain === 'governance') return [...common, 'certificate/proof source is fresh enough for the current dist'];
  return common;
}

function risksForDomain(domain: CapabilityDomain): string[] {
  if (domain === 'self-evolution') return ['promotion from benchmark overfit', 'forged receipt accepted as authority', 'candidate expands power faster than proof'];
  if (domain === 'memory') return ['procedural lesson without provenance', 'hash-chain break hidden by best-effort reads', 'local success reused outside its domain'];
  if (domain === 'immune') return ['counterexample corpus goes stale', 'briefing mistaken for a hard gate', 'false negative disproof creates fake confidence'];
  if (domain === 'discovery') return ['novelty search rewards noise', 'fitness metric improves local behavior while degrading system truth', 'candidate variant bypasses admission'];
  if (domain === 'runtime') return ['command escapes sandbox', 'temp/process abuse', 'green result from cached or unobserved side effect'];
  if (domain === 'governance') return ['certificate drift', 'dist/source mismatch', 'host boundary not proven'];
  if (domain === 'code-editing') return ['wrong symbol or occurrence selected', 'syntax passes while behavior regresses', 'unrelated dirty work is overwritten'];
  return ['capability has weak domain classification', 'proof requirement may be incomplete'];
}

function requiredProofsForTool(name: string, domain: CapabilityDomain): string[] {
  const proofs = ['node build.mjs', 'npx tsc --noEmit'];
  if (name === 'atomic_expand_self') proofs.push('node gates/self-expansion-validator-lattice.proof.mjs --json', 'node gates/security-monotonicity.proof.mjs --json', 'node gates/self-expansion-unexpected-effects.proof.mjs --json', 'node gates/self-expansion-real-self-evolution.proof.mjs --json');
  else if (name === 'atomic_self_evolution') proofs.push('node gates/self-evolution-harness.proof.mjs --json', 'node gates/self-evolution-mcp-tool.proof.mjs --json', 'node gates/self-evolution-archive-persistence.proof.mjs --json');
  else if (domain === 'memory') proofs.push('node gates/lesson-ledger.proof.mjs --json', 'node gates/self-evolution-lesson-rules.proof.mjs --json');
  else if (domain === 'immune') proofs.push('node gates/self-evolution-disproof-consumer.proof.mjs --json', 'node gates/self-evolution-disproof-briefing.proof.mjs --json');
  else if (domain === 'discovery') proofs.push('node gates/generator-nonllm.proof.mjs --json', 'node paradigm-verify.mjs');
  else if (domain === 'runtime') proofs.push('node gates/atomic-exec-readonly-usability.proof.mjs --json', 'node gates/atomic-exec-indirection-denial.proof.mjs --json');
  else if (domain === 'governance') proofs.push('node gates/compiled-mcp-y-certificate.proof.mjs --json', 'node proof-chain.proof.mjs --json');
  else proofs.push('npm test');
  return Array.from(new Set(proofs));
}

function counterProofsForDomain(domain: CapabilityDomain): string[] {
  if (domain === 'self-evolution') return ['weakened candidate is rejected', 'forged receipt is rejected', 'archive-chain tamper is detected'];
  if (domain === 'memory') return ['hash-chain mutation is detected', 'query precision rejects unrelated lessons'];
  if (domain === 'immune') return ['known counterexample is selected against matching proposal', 'empty or forged corpus cannot certify safety'];
  if (domain === 'discovery') return ['lower-fitness candidate is not admitted to an occupied MAP-Elites cell', 'candidate cannot bypass hard gates'];
  if (domain === 'runtime') return ['write attempt in read-only sandbox is denied', 'indirect shell effect is refused without proof'];
  if (domain === 'governance') return ['stale dist/source mismatch blocks certificate', 'missing host reentry keeps whole-host Y blocked'];
  if (domain === 'code-editing') return ['stale sha256 write is refused', 'syntax-regressing edit does not reach disk'];
  return ['missing source registration keeps status unproven'];
}

function proofLimitsForDomain(domain: CapabilityDomain): string[] {
  if (domain === 'self-evolution') return ['Receipts prove deterministic admission over recorded facts, not universal future correctness.'];
  if (domain === 'memory') return ['Memory is procedural evidence only when the source receipt and effect remain replayable.'];
  if (domain === 'immune') return ['Disproofs falsify known walls; absence of a wall is not proof of global safety.'];
  if (domain === 'discovery') return ['Fitness is local and must not outrank hard invariants.'];
  if (domain === 'runtime') return ['Sandbox proof is host- and policy-dependent.'];
  return ['Registry exposes current evidence; it is not a substitute for running the listed proofs.'];
}

function statusForDomain(domain: CapabilityDomain, archive: SelfEvolutionArchiveSummary, lesson: { accepted: number; rejected: number }, qdCells: number): CapabilityStatus {
  if (domain === 'self-evolution') {
    if (archive.promoteCount > 0 && (archive.rejectCount > 0 || archive.counterExamples > 0)) return 'mixed';
    if (archive.promoteCount > 0 && archive.latestReceiptSha256) return 'promoted';
    if (archive.rejectCount > 0 || archive.counterExamples > 0) return 'rejected';
  }
  if (domain === 'memory') return lesson.accepted > 0 || lesson.rejected > 0 ? 'mixed' : 'unproven';
  if (domain === 'discovery') return qdCells > 0 ? 'mixed' : 'unproven';
  if (domain === 'immune') return archive.counterExamples > 0 || archive.rejectCount > 0 ? 'mixed' : 'unproven';
  return 'unproven';
}

function evidenceForTool(tool: DiscoveredTool, domain: CapabilityDomain, archive: SelfEvolutionArchiveSummary, lesson: { records: number; accepted: number; rejected: number; chainOk: boolean; error?: string }, qd: { cells: number; averageFitness: number }): CapabilityEvidenceReceipt[] {
  const receipts: CapabilityEvidenceReceipt[] = tool.sourceFiles.map((file, index) => ({ kind: 'source-file', source: file, sha256: tool.sourceSha256s[index] }));
  if (domain === 'self-evolution' && archive.exists) receipts.push({ kind: archive.latestDecision === 'promote' ? 'self-evolution-promotion-receipt' : 'self-evolution-archive-receipt', source: archive.path, sha256: archive.latestReceiptSha256 ?? archive.sourceSha256 ?? undefined, count: archive.jsonEntries, detail: { promoteCount: archive.promoteCount, rejectCount: archive.rejectCount, counterExamples: archive.counterExamples, requiredGateCount: archive.requiredGateCount } });
  if (domain === 'memory') receipts.push({ kind: 'lesson-ledger-chain', source: '.atomic/lesson-ledger.jsonl', count: lesson.records, detail: lesson });
  if (domain === 'discovery') receipts.push({ kind: 'map-elites-fitness', source: '.atomic/map-elites-archive.json', count: qd.cells, detail: qd });
  if (domain === 'immune' && (archive.counterExamples > 0 || archive.rejectCount > 0)) receipts.push({ kind: 'negative-evidence-corpus', source: archive.path, count: archive.counterExamples + archive.rejectCount });
  return receipts;
}

export function buildCapabilityGenomeRegistry(repoRoot: string): CapabilityGenomeRegistry {
  const discovered = discoverMcpTools(repoRoot);
  const archive = summarizeSelfEvolutionArchive(repoRoot);
  const lessonRecords = readLessonLedger(repoRoot);
  const lessonIntegrity = verifyLessonLedgerChain(lessonRecords);
  const lesson = { records: lessonRecords.length, accepted: lessonRecords.filter((r) => r.decision === 'accept').length, rejected: lessonRecords.filter((r) => r.decision === 'reject').length, chainOk: lessonIntegrity.ok, error: lessonIntegrity.error };
  const qdMetrics = computeMapElitesMetrics(getMapElitesArchive(repoRoot));
  const qd = { cells: qdMetrics.cellsFilled, averageFitness: qdMetrics.averageFitness };
  const capabilities = discovered.tools.map((tool): CapabilityGenome => {
    const domain = domainForTool(tool.name);
    return { id: `capability:${tool.name}`, toolName: tool.name, domain, status: statusForDomain(domain, archive, lesson, qd.cells), purpose: purposeForTool(tool.name, domain), preconditions: preconditionsForDomain(domain), risks: risksForDomain(domain), requiredProofs: requiredProofsForTool(tool.name, domain), counterProofs: counterProofsForDomain(domain), sourceFiles: tool.sourceFiles, evidenceReceipts: evidenceForTool(tool, domain, archive, lesson, qd), history: { selfEvolution: domain === 'self-evolution' ? archive : undefined, lessonLedger: domain === 'memory' ? lesson : undefined }, fitness: domain === 'discovery' ? qd : { requiredGateCount: archive.requiredGateCount || undefined }, lineage: domain === 'self-evolution' ? { parentId: archive.latestParentId, candidateId: archive.latestCandidateId } : {}, proofLimits: proofLimitsForDomain(domain) };
  });
  return { kind: 'atomic-capability-genome-registry', schemaVersion: 1, generatedAt: new Date().toISOString(), repoRoot, sourceDigest: sha256(stableJson({ tools: discovered.tools.map((tool) => ({ name: tool.name, sourceFiles: tool.sourceFiles, sourceSha256s: tool.sourceSha256s })), sourceFiles: discovered.sourceFiles, archiveSha256: archive.sourceSha256, lesson, qd })), capabilities, evidence: { toolsDiscovered: discovered.tools.length, sourceFilesScanned: discovered.sourceFiles, selfEvolutionArchive: archive, lessonLedger: lesson, qdArchive: qd }, invariants: ['capability power must not increase without proportional proof surface', 'promoted status requires a durable promotion receipt', 'negative evidence remains first-class evidence, not noise', 'fitness never outranks hard gates', 'memory without provenance is not knowledge'], proofLimits: ['The registry proves that capability DNA is present and receipt-linked; it does not execute every required proof.', 'Domain classification is deterministic over current tool names and may require enrichment as new organs appear.', 'Self-evolution evidence is only as current as the local archive and compiled server surface.'] };
}

export function verifyCapabilityGenomeRegistry(registry: CapabilityGenomeRegistry): CapabilityGenomeVerification {
  const failures: string[] = [];
  const warnings: string[] = [];
  if (registry.kind !== 'atomic-capability-genome-registry') failures.push('registry kind mismatch');
  if (registry.schemaVersion !== 1) failures.push('registry schema version mismatch');
  if (!/^[a-f0-9]{64}$/.test(registry.sourceDigest)) failures.push('sourceDigest is not sha256');
  if (registry.capabilities.length === 0) failures.push('no capabilities discovered');
  const ids = new Set<string>();
  for (const capability of registry.capabilities) {
    if (ids.has(capability.id)) failures.push(`duplicate capability id: ${capability.id}`);
    ids.add(capability.id);
    if (!capability.toolName) failures.push(`${capability.id} missing toolName`);
    if (!capability.purpose) failures.push(`${capability.id} missing purpose`);
    if (capability.preconditions.length === 0) failures.push(`${capability.id} missing preconditions`);
    if (capability.risks.length === 0) failures.push(`${capability.id} missing risks`);
    if (capability.requiredProofs.length === 0) failures.push(`${capability.id} missing required proofs`);
    if (capability.counterProofs.length === 0) failures.push(`${capability.id} missing counter proofs`);
    if (capability.sourceFiles.length === 0) failures.push(`${capability.id} missing source file provenance`);
    if (capability.evidenceReceipts.length === 0) failures.push(`${capability.id} missing evidence receipts`);
    if (capability.status === 'promoted' && !capability.evidenceReceipts.some((receipt) => receipt.kind.includes('promotion') && typeof receipt.sha256 === 'string')) failures.push(`${capability.id} is promoted without a promotion receipt`);
  }
  const names = new Set(registry.capabilities.map((c) => c.toolName));
  for (const required of ['atomic_expand_self', 'atomic_self_evolution', 'atomic_capability_genome']) if (!names.has(required)) failures.push(`missing required capability: ${required}`);
  if (!registry.capabilities.some((c) => c.domain === 'memory')) warnings.push('no memory capability discovered');
  if (!registry.capabilities.some((c) => c.domain === 'immune')) warnings.push('no immune capability discovered');
  if (!registry.capabilities.some((c) => c.domain === 'discovery')) warnings.push('no discovery capability discovered');
  if (!registry.evidence.lessonLedger.chainOk) failures.push(`lesson ledger chain is not valid: ${registry.evidence.lessonLedger.error ?? 'unknown error'}`);
  return { ok: failures.length === 0, failures, warnings };
}