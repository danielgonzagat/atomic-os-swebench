# Diretiva Claude Code — PROVA que o net APRENDE (finetuning real, corpus completo) — o gate pra ele ser o sugeridor autopoiético

**Carta.** Verdade por número; nada fingido. Objetivo único: **provar, por número, se o net (conexionista) APRENDE a generalizar** — o pré-requisito pra ele virar o **motor de sugestão/score** do loop autopoiético (Fase 2/3). **Offline** (classificador sobre dados guardados): **roda JÁ, sem DeepSeek, sem Modal** (independe da API caída). Sob `ATOMIC-DOUTRINA-UNIFICADA-PESOS-APRENDIVEIS.md`; segredos só por env; **script standalone read-only sobre o corpus — não toca o driver co-dono do Codex.**

## O que "aprender" significa aqui (a régua honesta)
- **Aprender = curva held-out SOBE com #bugs-de-treino + controle de rótulo-permutado fica CHÃO.** (É a forma real da Prova-1.) In-sample alto sozinho = **decora**, não conta.
- **Escada inegociável:** aprender (aqui) → sugerir/gerar (Fase 2) → **Elevação** (gate final). **Provar que aprende NÃO é provar que gera nem que eleva.** Mesmo aprendendo, o net é **sugeridor/score soft** (a prova do §1 é o guarda duro) — **não** o gerador de código novo. Não rebatize.

## Por que rodar agora (o que mudou)
O null foi em **12 bugs**, **logreg linear**, **uma passada**, **features grosseiras**. Agora há **1436 bugs / 1796 lições** e o net **nunca foi exposto a isso com treino de verdade**. Capacidade+otimização (MLP/boosting) já deu **0.093 held-out no corpus pequeno** — mas **corpus-cheio × features-ricas × treino-real** é **inédito**. É o teste justo que a observação "o net nunca teve a chance + precisa de finetuning real" exige.

## O experimento — matriz 2×2 + curva
**Dados:** corpus completo (1436 bugs / 1796 lições). Split **leave-one-BUG-out** (nenhum bug em treino e teste juntos). Validação **separada** do teste.

**Dois ALVOS (a pergunta WHERE vs HOW):**
- **CONTEÚDO** (alvo original): separar movimento-de-fix **certo vs errado** (o COMO).
- **PROCESSO** (alvo re-apontado): prever **classe-de-processo / produtividade-do-movimento** (o que recorre).

**Dois ENCODINGS:**
- **(a) grosseiro** (features atuais).
- **(b) rico** (efeito-por-passo + locus-causal + símbolos do problem_statement + nomes dos testes f2p).

→ **4 células** (alvo × encoding), cada uma medida igual.

**Treino REAL (a sua observação embutida):** **MLP** (não só linear), **épocas suficientes pra loss de treino convergir**, regularização (dropout/L2), **early-stop pela VALIDAÇÃO** (nunca pelo teste held-out). Reportar **in-sample E held-out** (pra ver overfit honesto).

**Protocolo anti-fachada:**
- **Curva de aprendizado:** held-out recall@FP0 vs #bugs-de-treino — **sobe?**
- **Controle permutado:** rótulos embaralhados → tem de ficar **chão**.
- **Sound:** recall@**FP0** (0 falso-positivo) + AUC + p@1/p@5.
- **Sem replay; sem vazar a resposta no rótulo** (retrieval pode usar nomes; o rótulo de correção, não).

## Critério de PROVA (por célula)
**Aprende** ⟺ curva held-out **SOBE** com N **E** permutado **CHÃO** **E** held-out **materialmente acima de 0.18** (ideal: cruza **0.25** pro uso-trava).
- **Conteúdo sobe** → net aprende a separar conteúdo cross-bug (seria a virada — improvável, mas é o teste).
- **Só processo sobe** → net aprende **processo** (re-aim confirmado); conteúdo segue no LLM.
- **Tudo chão mesmo com corpus-cheio + rico + treino-real** → muro de feature/colisão **confirmado em escala** — o net não é gerador de conteúdo, por número.

## Previsão honesta (pra calibrar, não pra enviesar)
Processo **provavelmente sobe** (recorre); conteúdo **provavelmente esbarra** (colisão de vetores idênticos — mais steps não separam entradas iguais de rótulo oposto). Nesse caso o net **aprende — como sugeridor/score soft de processo**, e entra na Fase 2/3 ranqueando candidatos **sob a prova**; o **gerador** de código novo continua sendo **composição-de-operadores + prova**, não o net. Mas é previsão — **o número decide**, e eu mudo de opinião por número.

## Guardas
Offline (sem DeepSeek/Modal); standalone read-only (não toca driver co-dono); **non-claim até medir**; null em qualquer célula é **informação** (grava no LEDGER); **nunca conte "aprende" como "gera" nem "eleva"**; sem replay/vazamento; validação ≠ teste.

## Próximo passo exato
Construir o experimento (4 células + curva + permutado), rodar **offline agora**, e gravar no LEDGER a **matriz (alvo × encoding): in-sample / held-out / slope-da-curva / permutado**. O número que importa: **alguma célula tem curva held-out subindo, permutado chão, e cruza 0.25?**
- **Sim** → o net **APRENDE** (naquele alvo) → ganha papel de sugeridor/score no loop autopoiético (sob prova).
- **Não** → muro confirmado em escala e com treino real → o net sai de "talvez" para "não, por número" — e o gerador autopoiético depende de composição-de-operadores+prova, não do net.

Sem número fresco no LEDGER, é deriva. Provado por número, jamais por desejo.
