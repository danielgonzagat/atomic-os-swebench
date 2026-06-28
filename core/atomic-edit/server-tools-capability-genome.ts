import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { resolveAllowedRootForAbsolutePath } from './guard.js';
import { buildCapabilityGenomeRegistry, verifyCapabilityGenomeRegistry, type CapabilityDomain } from './server-helpers-capability-genome.js';
import { ok, fail } from './server-helpers-result.js';

const DOMAIN_VALUES = ['code-editing', 'self-evolution', 'memory', 'immune', 'discovery', 'runtime', 'governance', 'unknown'] as const;

function atomicSourceRoot(): string {
  const here = path.dirname(fileURLToPath(import.meta.url));
  return path.basename(here) === 'dist' ? path.resolve(here, '..') : here;
}

function resolveRegistryRoot(rawRoot: string | undefined): string {
  if (!rawRoot || rawRoot.trim().length === 0) return atomicSourceRoot();
  const abs = path.resolve(rawRoot);
  const allowedRoot = resolveAllowedRootForAbsolutePath(abs);
  if (!allowedRoot) throw new Error(`repoRoot is outside the Atomic allowed roots: ${abs}`);
  return abs;
}

export function registerToolsCapabilityGenome(server: McpServer): void {
  server.registerTool(
    'atomic_capability_genome',
    {
      title: 'Atomic capability genome registry',
      description:
        'Builds a live, read-only capability genome from the current MCP tool source, self-evolution archive, lesson ledger, ' +
        'disproof history, and QD fitness evidence. Each capability carries purpose, domain, preconditions, risks, required ' +
        'proofs, counter-proofs, provenance, fitness, lineage, and proof limits. This is the neuro-symbolic capability DNA ' +
        'surface for turning Atomic from a tool list into an evolvable organism.',
      inputSchema: {
        domain: z.enum(DOMAIN_VALUES).optional().describe('Optional domain filter.'),
        toolName: z.string().optional().describe('Optional exact MCP tool name filter.'),
        includeUnproven: z.boolean().optional().describe('Include capabilities that only have source provenance. Defaults to true.'),
        repoRoot: z.string().optional().describe('Optional repo root override inside the Atomic allowed roots.'),
      },
    },
    async (a) => {
      try {
        const root = resolveRegistryRoot(a.repoRoot);
        const registry = buildCapabilityGenomeRegistry(root);
        const verification = verifyCapabilityGenomeRegistry(registry);
        if (!verification.ok) return fail(`capability genome verification failed: ${verification.failures.join('; ')}`);

        const includeUnproven = a.includeUnproven !== false;
        const filtered = registry.capabilities.filter((capability) => {
          if (a.toolName && capability.toolName !== a.toolName) return false;
          if (a.domain && capability.domain !== (a.domain as CapabilityDomain)) return false;
          if (!includeUnproven && capability.status === 'unproven') return false;
          return true;
        });

        return ok({
          ok: true,
          changed: false,
          registry: {
            ...registry,
            capabilities: filtered,
          },
          verification,
          filters: {
            domain: a.domain ?? null,
            toolName: a.toolName ?? null,
            includeUnproven,
            returnedCapabilities: filtered.length,
            totalCapabilities: registry.capabilities.length,
          },
          proofLimits: [
            'This tool builds and verifies the capability DNA registry; it does not execute every required proof listed per capability.',
            'A capability with source provenance only remains unproven until receipts, lessons, disproofs, or fitness evidence exist.',
            'Promoted status is refused unless tied to a durable promotion receipt.',
          ],
        });
      } catch (error) {
        return fail(error instanceof Error ? error.message : String(error));
      }
    },
  );
}