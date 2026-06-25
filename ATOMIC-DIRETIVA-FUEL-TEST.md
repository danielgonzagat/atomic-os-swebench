# Diretiva — Teste do combustível: WHERE-fuel vs HOW-fuel (lesson-ledger por efeito)

**Contexto (teu número, registrado).** Lesson-ledger total = **1796 lições / 1436 bugs distintos**. Recuperação cross-bug por efeito (leave-one-bug-out): era 0.08 em n=25 → agora **p@1=0.18, p@5=0.43, cobertura=0.82** (Pro: p@1=0.19, p@5=0.54, cobertura=0.88). Veredito honesto: **densidade tirou a Fase 1 do null, mas NÃO resolveu.** Os clusters/locus existem em escala (cobertura 0.82); o ranqueamento por efeito é fraco (p@1=0.18). O gargalo mudou de **dado** → **encoding-de-efeito**.

**A distinção que define o próximo passo (não pule).** p@1/p@5 medem **recuperação de operador-de-LOCUS/efeito = combustível-de-WHERE.** Pelo achado **0-fix-shape**, o CONTEÚDO difere no mesmo locus — então recuperar um operador **não prova** que aplicá-lo resolve. O que falta provar é se o combustível é **HOW-fuel** (conteúdo transferível), não só WHERE-fuel. É isso que o experimento abaixo mede.

## O experimento — dois números, nesta ordem

**A) Encoding-de-efeito mais fino → re-medir recuperação.** Trocar a assinatura grosseira (superfície-de-teste) por **efeito-por-passo dos traces instrumentados + locus-causal**. Re-rodar leave-one-bug-out. **Números:** p@1, p@5, cobertura — **com controle de rótulo-permutado plano** (senão é vazamento). Alvo: p@1 sobe materialmente acima de 0.18 e o permutado fica chão.

**B) O número DECISIVO (WHERE-fuel vs HOW-fuel).** Para cada bug held-out: pegar os **top-5 operadores recuperados**, o gerador **compõe/aplica** cada um, passa pela **catraca de prova**, e mede **quantos RESOLVEM o bug held-out** (scoring oficial).
- **`resolve@5` held-out, sem replay, com controle** — este é o número que separa **WHERE-fuel (≈0)** de **HOW-fuel (>0)**.
- Reportar também **% de candidatos NOVOS (não-replay) E sound** — geração real, não memória.

## Guardas (inegociáveis)
- **Escada honesta:** recuperação (A) → `resolve@5` (B) → **Elevação** (gate final, Pro coluna-frontier). **Não conte recuperação como geração, nem geração como Elevação.** 0.18/0.43 **não é vitória** — é meio-caminho-do-combustível.
- **Sem replay, sem vazamento de problem-statement, controle permutado plano** em A e B. Proveniência Pro oficial por `instance_id`.
- **Non-claim até medir;** nada de número fabricado; **null em qualquer etapa é informação** — registra no LEDGER.
- Só via `expand_self`; **não tocar driver co-dono se Codex vivo**; segredos só por env; estudante só DeepSeek V4 Pro.

## Próximo passo exato
Implementar (A) o encoding **efeito-por-passo** + re-medir p@1/p@5/cobertura held-out com permutado. **Se p@1 subir**, rodar (B) **`resolve@5` held-out** dos top-5 compostos+provados. Gravar os dois números no LEDGER.
- **`resolve@5` > 0 held-out (sem replay) = a primeira evidência de HOW-fuel — o combustível de verdade da Fase 2.**
- **`resolve@5` = 0 mesmo com p@1 alto = WHERE-fuel confirmado;** o conteúdo segue no LLM, e a Fase 2 autônoma não tem combustível de geração (registra honesto, sem fingir).

Sem número fresco no LEDGER, é deriva. Provado por número, jamais por desejo.
