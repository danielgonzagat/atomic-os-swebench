import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { resolveSafeTarget, REPO_ROOT } from './guard.js';
import { recordLesson, queryLessonsByEffect, readLessonLedger, verifyLessonLedgerChain } from './server-helpers-lesson-ledger.js';
import { generateProposalsWithoutLlm } from './server-helpers-generator-nonllm.js';
import { updateMapElitesArchive, getMapElitesArchive, computeMapElitesMetrics } from './server-helpers-qd.js';
import { ok, fail } from './server-helpers-result.js';

export function registerToolsLessonLedger(server: McpServer): void {
  server.tool(
    'atomic_lesson_record',
    {
      decision: z.enum(['accept', 'reject']).describe('Outcome of the self-expansion run'),
      operator: z.object({
        file: z.string().describe('File path of the operation'),
        op: z.enum(['create', 'replace', 'delete', 'replace_text']).describe('Operator type'),
        oldText: z.string().optional().describe('Original text replaced'),
        newText: z.string().optional().describe('Replacement text'),
        occurrence: z.number().optional().describe('Occurrence index'),
      }).describe('The change/mutation applied during the run'),
      effect: z.object({
        gatesFlipped: z.array(z.string()).describe('List of gates that changed status (e.g. gates/some.proof:RED->GREEN)'),
        veredictDelta: z.string().optional().describe('Delta of overall run verdict'),
        floorDelta: z.array(z.object({
          file: z.string(),
          bytesRemoved: z.number(),
          bytesAdded: z.number(),
          op: z.string(),
        })).optional().describe('Delta of byte floor modifications'),
      }).describe('The verified effect/outcome of the mutation'),
      context: z.object({
        intent: z.string().optional().describe('Developer intent / task context'),
        preflightError: z.string().optional().describe('Error message if rejected during preflight'),
        durationMs: z.number().optional().describe('Execution duration in milliseconds'),
        ts: z.number().optional().describe('Timestamp of execution'),
      }).optional().describe('Metadata/context of the run'),
      repoRoot: z.string().optional().describe('Optional repo root path override'),
    },
    async (a) => {
      try {
        const root = a.repoRoot || REPO_ROOT;
        const result = recordLesson(root, {
          decision: a.decision,
          operator: a.operator,
          effect: a.effect,
          context: a.context,
        });
        if (!result) return fail('Failed to write lesson record to the ledger');
        return ok({ lesson: result });
      } catch (e) {
        return fail(e instanceof Error ? e.message : String(e));
      }
    }
  );

  server.tool(
    'atomic_lesson_query',
    {
      gatesFlipped: z.array(z.string()).optional().describe('Gates to search for matching transitions'),
      targetFile: z.string().optional().describe('Target file affected by the operator'),
      decision: z.enum(['accept', 'reject']).optional().describe('Filter by accepted or rejected runs'),
      repoRoot: z.string().optional().describe('Optional repo root path override'),
    },
    async (a) => {
      try {
        const root = a.repoRoot || REPO_ROOT;
        const matches = queryLessonsByEffect(root, {
          gatesFlipped: a.gatesFlipped,
          targetFile: a.targetFile,
          decision: a.decision,
        });
        return ok({ matches });
      } catch (e) {
        return fail(e instanceof Error ? e.message : String(e));
      }
    }
  );

  server.tool(
    'atomic_lesson_verify_chain',
    {
      repoRoot: z.string().optional().describe('Optional repo root path override'),
    },
    async (a) => {
      try {
        const root = a.repoRoot || REPO_ROOT;
        const ledger = readLessonLedger(root);
        const integrity = verifyLessonLedgerChain(ledger);
        if (!integrity.ok) {
          return fail(integrity.error || 'Chain verification failed');
        }
        return ok({ ok: true, records: ledger.length });
      } catch (e) {
        return fail(e instanceof Error ? e.message : String(e));
      }
    }
  );

  server.tool(
    'atomic_generator_nonllm',
    {
      failedGateCommand: z.string().describe('The command of the failed gate (e.g. node gates/some.proof.mjs --json)'),
      repoRoot: z.string().optional().describe('Optional repo root path override'),
    },
    async (a) => {
      try {
        const root = a.repoRoot || REPO_ROOT;
        const proposals = generateProposalsWithoutLlm(root, a.failedGateCommand);
        return ok({ proposals });
      } catch (e) {
        return fail(e instanceof Error ? e.message : String(e));
      }
    }
  );

  server.tool(
    'atomic_qd_archive_update',
    {
      lessonId: z.string().describe('The ID of the lesson to evaluate for the QD archive'),
      repoRoot: z.string().optional().describe('Optional repo root override'),
    },
    async (a) => {
      try {
        const root = a.repoRoot || REPO_ROOT;
        const ledger = readLessonLedger(root);
        const lesson = ledger.find((l) => l.lessonId === a.lessonId);
        if (!lesson) return fail(`Lesson ${a.lessonId} not found in ledger`);
        const result = updateMapElitesArchive(root, lesson);
        return ok({ admitted: result.admitted, isNewCell: result.isNewCell, isImprovement: result.isImprovement });
      } catch (e) {
        return fail(e instanceof Error ? e.message : String(e));
      }
    }
  );

  server.tool(
    'atomic_qd_archive_get',
    {
      repoRoot: z.string().optional().describe('Optional repo root override'),
    },
    async (a) => {
      try {
        const root = a.repoRoot || REPO_ROOT;
        const archive = getMapElitesArchive(root);
        const metrics = computeMapElitesMetrics(archive);
        return ok({ archive, metrics });
      } catch (e) {
        return fail(e instanceof Error ? e.message : String(e));
      }
    }
  );
}
