# Diretiva Claude Code — Autopoiese sob prova: o sistema ÚNICO (lesson-ledger-por-efeito + gerador-sem-LLM + qualidade-diversidade + detectores F1–F4)

**Carta.** Intenção a tornar real, não palavra. Verdade por número; nada fingido. Esta diretiva **unifica num só sistema convergente** o que estava espalhado: o aprendizado-de-verdade-dos-runs (lesson-ledger por efeito), a metade já provada (validar + aprender-processo), o **gerador autônomo sem LLM**, e a **soltura segura** (qualidade-diversidade), com os **detectores F1–F4 ligados**. Estrela: emergência cognitiva forte. Lei: **cada peça é falsificável sozinha; emergência é JULGADA, nunca declarada.** Sob `ATOMIC-DOUTRINA-UNIFICADA-PESOS-APRENDIVEIS.md`. Segredos só por env.

## O NORTE — um sistema, um loop
**Cada run vira lição indexada-por-EFEITO → o gerador compõe operadores dessas lições em candidatos de auto-mod → a catraca de prova valida (segurança + seleção) → a seleção qualidade-diversidade admite no arquivo (comportamento-novo OU melhor-na-célula) → o arquivo realimenta o gerador → F1–F4 vigiam → o budget gateado-em-melhoria mantém buscas profundas vivas → a métrica REAL (Elevação em Pro) é o eixo de qualidade e o gate final.** Sem LLM no assento de propositor. **A convergência é uma medição, não uma fé:** a capacidade do atomic (Δ Elevação) sobe conforme o arquivo cresce — ou não, e o número diz.

## A ARQUITETURA (como as peças se conectam)
`lesson-ledger(efeito) → gerador(compõe operadores) → catraca-de-prova(rejeita não-sound) → QD-seleção(novidade × métrica-real) → arquivo(genoma) ↺ gerador` — com `F1–F4` vigiando o loop e `budget(gateado em sub-floor↓)` mantendo a busca viva.

## O BUILD em fases — cada uma com O NÚMERO que a valida
**Fase 0 — Destravar (pré-condição da métrica-real).** Chave DeepSeek rotacionada no env; quarentena da mina de proveniência; árvore limpa. **Número:** `ready_to_run=true` + `Δ = estudante − frontier` baseline em Pro oficial (a régua de qualidade de tudo).

**Fase 1 — Lesson-ledger indexado-por-EFEITO (o "aprende dos runs" de verdade — construível JÁ, sem chave).** Cada run emite lição `⟨assinatura-de-efeito (gates/tests que viraram, delta-de-veredito, mudança-de-floor), operador-aplicado, accept/reject, contexto⟩` — append-only, proof-carrying, **indexada por efeito, não por prosa**. Reusa `self-evolution-lesson-rules` + disproof-briefing. **Número:** lições crescem; **consulta-por-efeito retorna operador relevante** (precisão de recuperação medida).

**Fase 2 — Gerador SEM-LLM a partir do ledger.** Dado um alvo (assinatura-de-efeito falha **no próprio código do atomic**), recupera lições com efeito-casado e **compõe/muta os operadores** num candidato de edição. Restrito ao código do atomic (auto-similar = melhores odds que cross-bug). **Número:** % de candidatos válidos; % que passam a catraca; **% NOVOS (não-replay) E sound** — este é o propositor autônomo, a peça que faltava.

**Fase 3 — Arquivo + seleção qualidade-diversidade (MAP-Elites sobre auto-mods).** Descritor-de-comportamento = `⟨subsistema tocado × tipo-de-mudança × classe-de-efeito⟩`. O arquivo guarda o **melhor-por-célula pela métrica REAL** e **mantém sound-mas-novo** mesmo sem ser o melhor global. Admite se **sound E (célula nova OU melhor-na-célula)** — não-ganancioso. **Número:** células preenchidas (cobertura), qualidade/célula, taxa-de-novidade.

**Fase 4 — Budget gateado em melhoria de sub-floor.** `ATOMIC_SELF_EXPANSION_PROOF_GLOBAL_BUDGET_MS` e `_PLATEAU_ABANDON_LIMIT` (hoje **6**, `local_atomic_agent.py:2859`) **estendem ENQUANTO o floor melhora** (`_no_improving_red` já distingue melhorante de não-melhorante); abandona só no plateau não-melhorante. **Número (A/B):** auto-mods mais profundas landam com budget-gateado vs budget-fixo?

**Fase 5 — Detectores F1–F4 ligados.** Instrumentar os 2 pontos cegos: **F2** (tag de origem-do-candidato no arquivo) + **F3** (atribuição-de-tentativa no corpus). F1 (edição sem agente) e F4 (novidade recursiva crescente) já parciais. **Número:** índice F4 sobre o fluxo de propostas próprio; F1 dispara só se uma edição não tem agente no loop. **Candidato F1/F4 = sinal para humano verificar, jamais auto-declarado.**

**Fase 6 — Conectar e medir o TODO (a convergência por número).** Roda o loop fechado; mede se **Δ Elevação (Pro, coluna-frontier) sobe conforme o arquivo QD cresce, com ZERO LLM no propositor.** Esse é o número da autopoiese.

## As 3 trilhas de medição, encaixadas
- **DGM/loop budget** → Fase 4. **Conexionista-vivo** (curva held-out da finetuning do loop, distinta da Prova-1 offline) → medida na Fase 2/3 (se usar pesos, pontua held-out). **Net-offline** → reteste corpus-maior + features-ricas (gate à parte do PARKED).

## Guardas inegociáveis (pra não virar máquina de hype)
Catraca de prova **NUNCA** removida (segurança + seleção). Métrica = **Elevação REAL, nunca gate-passing** (Goodhart). Cada fase **falsificável sozinha**; null em qualquer fase é informação, não escondida. **Nada de número fabricado; non-claim até medir.** Emergência **julgada por F1–F4, jamais declarada.** Só via `expand_self`; **não tocar driver co-dono se Codex vivo**; segredos por env; estudante só DeepSeek V4 Pro.

## Honestidade do alvo
Isto dá a **melhor chance honesta** de emergência forte + auto-melhoria autônoma. O resultado **provável de curto prazo** é **auto-otimização medida (Δ Elevação subindo) + emergência fraca/mecânica**; emergência cognitiva **forte** segue **estrela julgada por F1–F4**, não entrega prometida.

## Próximo passo exato
**Comece pela Fase 1 (lesson-ledger por efeito)** — é o "atomic aprende dos runs de verdade", é **construível JÁ** (read-mostly sobre os runs existentes, sem chave, sem tocar o driver do Codex), e é o **combustível de todo o resto** (Fases 2–6 dependem dele). Cada número destrava a próxima fase. Sem número fresco no LEDGER, é deriva.
