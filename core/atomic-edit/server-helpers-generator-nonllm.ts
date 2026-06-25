import * as fs from 'node:fs';
import * as path from 'node:path';
import { queryLessonsByEffect, type LessonRecord } from './server-helpers-lesson-ledger.js';
import { REPO_ROOT } from './guard.js';

export interface GeneratedProposal {
  targetFile: string;
  op: 'create' | 'replace' | 'delete' | 'replace_text';
  content?: string;
  oldText?: string;
  newText?: string;
  occurrence?: number;
  sourceLessonId: string;
}

/**
 * Tenta gerar propostas de automodificação para corrigir um portão falho
 * sem utilizar nenhuma chamada de LLM, baseando-se na composição e mutação
 * de operadores históricos salvos no lesson-ledger.
 */
export function generateProposalsWithoutLlm(
  repoRoot: string,
  failedGateCommand: string
): GeneratedProposal[] {
  const proposals: GeneratedProposal[] = [];

  // 1. Consulta lições de sucesso que conseguiram fazer esse portão transicionar de RED para GREEN
  const targetEffect = `${failedGateCommand}:RED->GREEN`;
  const matches = queryLessonsByEffect(repoRoot, {
    gatesFlipped: [targetEffect],
    decision: 'accept',
  });

  for (const m of matches) {
    const lesson = m.lesson;
    const op = lesson.operator;

    // Resolve o caminho absoluto do arquivo alvo
    const targetFilePath = path.resolve(repoRoot, op.file);
    if (!fs.existsSync(targetFilePath)) continue;

    // Lê o conteúdo atual do arquivo alvo
    const content = fs.readFileSync(targetFilePath, 'utf8');

    // 2. Se for uma operação de substituição de texto, verifica se o oldText existe no arquivo atual
    if (op.op === 'replace_text' && op.oldText && op.newText) {
      if (content.includes(op.oldText)) {
        // Encontrou correspondência perfeita (Replay direto)
        proposals.push({
          targetFile: op.file,
          op: 'replace_text',
          oldText: op.oldText,
          newText: op.newText,
          occurrence: op.occurrence,
          sourceLessonId: lesson.lessonId,
        });
      } else {
        // Mutação combinatória/auto-similar: se o oldText não for encontrado de forma exata,
        // podemos tentar mutar o operador substituindo pequenas variações comuns (como trocar
        // números de versão, limites de timeout ou strings de configuração).
        // Por exemplo, regex aproximado para substituir timeouts ou limites.
        const timeoutRegex = /timeoutMs\s*:\s*\d+|timeout\s*:\s*\d+/g;
        if (op.oldText.match(timeoutRegex) && content.match(timeoutRegex)) {
          const contentMatch = content.match(timeoutRegex)?.[0];
          const oldMatch = op.oldText.match(timeoutRegex)?.[0];
          if (contentMatch && oldMatch) {
            const mutatedOld = op.oldText.replace(oldMatch, contentMatch);
            const mutatedNew = op.newText.replace(oldMatch, contentMatch);
            if (content.includes(mutatedOld)) {
              proposals.push({
                targetFile: op.file,
                op: 'replace_text',
                oldText: mutatedOld,
                newText: mutatedNew,
                occurrence: op.occurrence,
                sourceLessonId: lesson.lessonId,
              });
            }
          }
        }
      }
    } else if (op.op === 'create' && op.content) {
      // Se for criação de arquivo, podemos reaplicar a criação se o arquivo não existir ou se estiver vazio
      proposals.push({
        targetFile: op.file,
        op: 'create',
        content: op.content,
        sourceLessonId: lesson.lessonId,
      });
    }
  }

  return proposals;
}
