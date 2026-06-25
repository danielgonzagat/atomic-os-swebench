# Diretiva Claude Code — Elevação por PROCESSO, medida SÓ em SWE-Bench Pro oficial

**Carta.** Intenção a tornar real, não palavra a obedecer. Verdade por número; nada fingido. Supera a diretiva net-supervisionado (a Prova-1 deixou o fix-content-net PARKED/NULL) e incorpora a verificação adversarial de 3 revisores. Sob `ATOMIC-DOUTRINA-UNIFICADA-PESOS-APRENDIVEIS.md`. Credenciais só por variável de ambiente.

## 0. O fato que pivota (Prova 1 — adversarialmente verificada)

- Net de fix-content cross-bug: held-out leave-one-bug-out **recall@FP0 ≈ 0** (melhor honesto ~0.167, acima do acaso ~0.05, **abaixo da barra 0.25**); in-sample ~0.85–1.0 = **decora**; controle permutado idêntico; curva plana. 5 agentes × 4 ângulos, **nenhum cruzou a barra**.
- Mecânica: cross-bug, o movimento certo de um bug fica **vetor-idêntico** ao errado de outro (o COMO do fix é bug-específico) → nenhum classificador separa vetores idênticos.
- **Honestidade (correção):** o gap 0.167↔0.25 é **subdimensionado** (12 bugs). É **null, não refutação**. Por isso o net **não morre — fica PARKED** (§1).
- **Não promover:** "+4/8" (hardcode task-specific XDG/appdirs) e contratos VSA sintéticos (same=1.0) = **verde-fingido. Proibido.**

## 1. O net de fix-content fica PARKED (não kill), com portão pré-registrado

Não gaste round amplificando-o agora. Side-quest falsificável, barato, **em SWE-Bench Pro oficial**: escalar para **≥50–100 bugs Pro**, refit, **um** número held-out recall@FP0. **>0.25 → revive; ≤0.20 → mata de vez.** Rótulos de graça (scoring Docker). Sem isso, "morto" seria autoengano a partir de teste fraco.

## 2. AMPLIFICAR (o que já eleva e transfere cross-bug — o foco do esforço)

- **Guards de processo** (~30 → **paridade** DeepSeek≈Claude). Minere/afine mais: cada classe de fracasso-de-processo transfere.
- **Eliminação WITHIN-TASK** (re-disparo bloqueando, neste bug, os movimentos provados-errados). **Sound** (a colisão é cross-bug). ~56% de churn evitável, medido. Aprofunde.
- **Navegação/WHERE** + **piso de correção** (lei do byte) + percepção/compaction.

## 3. MEDIR — SÓ tasks oficiais do SWE-Bench Pro, com COLUNA-FRONTIER pareada

Regra dura, anti-fachada e anti-contaminação:

- **Apenas tasks oficiais do SWE-Bench Pro.** Nada de synthetic, nada de subset "network-free" cherry-picked, nada de Verified. (O ELIM1 atual, em 7 tasks network-free, **não** satisfaz isto — re-rode em Pro oficial.)
- **Proveniência da task é parte da métrica:** o scorer usar `ScaleAI/SWE-bench_Pro` não basta; `PROBLEM.md`, `meta.json`, `dataset_name`, `benchmark_label` e `instance_id` precisam provar que o diretório local veio do Pro oficial. Mistura Pro scorer + prompt/meta Verified = byte-negativo.
- **A Elevação é a coluna-frontier pareada:** `solve_rate(DeepSeek-V4-Pro + atomic) − solve_rate(baseline frontier)` nos **MESMOS task-IDs Pro**, held-out, scoring Docker oficial, baseline congelado. A baseline precisa carregar recibo explícito: `baseline_role=frontier`, `frozen=true`, `official_docker=true`, `benchmark_suite=swe_bench_pro`, `dataset_name=ScaleAI/SWE-bench_Pro`, `benchmark_label=SWE-bench-Pro`, e `task_ids` exatamente pareados. **Sem a coluna-frontier e esse recibo, não existe alegação de Elevação.**
- **Paridade ≠ meta.** O alvo é **fraco > frontier, com margem CRESCENTE** conforme o acúmulo. Paridade (dentro do IC do frontier) é resultado real, mas **não é a meta — nunca rebatize paridade como surpasse.**
- **ELIM1 / within-task (best-of-K vs elim-K) mede EFICIÊNCIA de busca, não Elevação.** É necessário, não suficiente: um delta positivo lá é intra-método, no mesmo modelo — **só vira evidência de meta quando pareado com a coluna-frontier nos mesmos IDs Pro.** Não conte um pelo outro.

## 4. Re-escopo honesto

O substrato faz a **geração do LLM ATERRISSAR mais** (processo+navegação+verificação+eliminação) — não substitui a geração por memória-de-fix (PARKED por Prova-1 NULL). Aprende e transfere o **simbólico de processo + verificação**. **Fraco→paridade: provado (em Verified). Fraco→superar em Pro oficial: a meta não-provada, a medir com a coluna-frontier.** AGI/substituir-NN = estrela, não entrega.

## 5. Guardas + próximo passo exato

**Guardas:** só o MCP atomic, só generalista, tudo por `expand_self` monotônico; **não** tocar driver co-dono se Codex vivo; **nunca** finja verde / fabrique número / conte paridade-ou-eficiência como Elevação; segredos por env; estudante só DeepSeek V4 Pro.

**Próximo passo exato:** com a árvore limpa, montar o harness de Elevação em **SWE-Bench Pro oficial** com a **coluna-frontier pareada** (mesmos IDs, Docker); rodar o estudante (DeepSeek+atomic) e o baseline-frontier nesses IDs; reportar `Δ = estudante − frontier` e a **curva de Δ vs acúmulo**. ELIM1 re-rodado em Pro oficial entra como dimensão de eficiência, não como Elevação. Registrar números reais no LEDGER. Sem número fresco, está derivando.
