import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { synthesizeMetaOperator, DEFAULT_STRING_REPLACE_ISLAND } from './engine-meta-synth.js';
import { verifyProofReceipt } from './engine-synthesis-kernel.js';
import { ok, fail } from './server-helpers-result.js';

const ExampleSchema = z.object({ input: z.string(), output: z.string() });

export function registerToolsMetaSynth(server: McpServer): void {
  server.registerTool(
    'atomic_meta_synth',
    {
      title: 'Atomic meta-synthesis kernel',
      description:
        'Runs the neuro-symbolic synthesis kernel over a bounded string-rewrite island and returns canonical receipts. ' +
        'Heuristic candidates are never promotion eligible; only verified formal PROVEN receipts can be considered by self-evolution.',
      inputSchema: {
        name: z.string().optional().describe('Optional synthesis island name'),
        train: z.array(ExampleSchema).optional().describe('Training examples for a string rewrite island'),
        heldOut: z.array(ExampleSchema).optional().describe('Held-out examples for the same string rewrite island'),
        allowCvc5: z.boolean().optional().describe('Run CVC5 when reachable; false still returns honest receipt data'),
        cvc5Bin: z.string().optional().describe('Explicit cvc5 executable path'),
        pythonBin: z.string().optional().describe('Explicit Python executable with the cvc5 module installed'),
        verifyReceipt: z.record(z.string(), z.unknown()).optional().describe('Receipt to verify without synthesizing a new island'),
      },
    },
    async (a) => {
      try {
        if (a.verifyReceipt) {
          return ok({ ok: true, changed: false, verification: verifyProofReceipt(a.verifyReceipt as never) });
        }
        const custom = Array.isArray(a.train) || Array.isArray(a.heldOut);
        if (custom && (!Array.isArray(a.train) || !Array.isArray(a.heldOut))) {
          throw new Error('custom meta-synthesis requires both train and heldOut examples');
        }
        const problem = custom
          ? { name: a.name ?? 'custom_string_replace_island', train: a.train ?? [], heldOut: a.heldOut ?? [] }
          : DEFAULT_STRING_REPLACE_ISLAND;
        const result = synthesizeMetaOperator(problem, {
          allowCvc5: a.allowCvc5 === true,
          cvc5Bin: a.cvc5Bin,
          pythonBin: a.pythonBin,
        });
        return ok({
          ...result,
          changed: false,
          summaryForHuman: result.promotionEligible
            ? `meta-synth produced a formal PROVEN receipt for ${result.name}`
            : `meta-synth returned receipts for ${result.name}; no automatic promotion is allowed without a formal PROVEN receipt`,
        });
      } catch (error) {
        return fail(error instanceof Error ? error.message : String(error));
      }
    },
  );
}
