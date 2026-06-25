# Diretiva Claude Code — PROVA da Elevação em SWE-Bench Pro oficial (foco único, API de volta)

**Carta.** Verdade por número; nada fingido. **Foco único, agora:** medir, em **SWE-Bench Pro oficial**, se o **atomic eleva o resultado do DeepSeek** — e quanto. O net-aprendiz está **morto por número** (4 instrumentos, trava ≤0.20 honrada) — **não gaste mais nenhum round nele.** Tudo nesta rodada é a medição de Elevação. Sob `ATOMIC-DOUTRINA-UNIFICADA-PESOS-APRENDIVEIS.md`. **Credenciais rotacionadas, só por env** — as coladas no chat são vazadas, não as use; rotacione e exporte `DEEPSEEK_API_KEY`/`MODAL_TOKEN_ID`/`MODAL_TOKEN_SECRET` no ambiente.

## A pergunta, em DOIS números (não confunda)
1. **LIFT — "o atomic eleva o DeepSeek?" (a pergunta direta, número PRIMÁRIO):**
   `lift = solve_rate(DeepSeek-V4-Pro + atomic) − solve_rate(DeepSeek-V4-Pro SOZINHO)` nos **MESMOS task-IDs Pro**. É **within-model** (mesmo modelo, ±atomic) → **sem confound de frontier.** Este é o número que responde "o Atomic realmente eleva o modelo barato".
2. **vs FRONTIER — "chega/supera o caro?" (esticão, número SECUNDÁRIO):**
   `Δ = solve_rate(DeepSeek + atomic) − solve_rate(baseline frontier)` nos mesmos IDs. Paridade (IC sobrepõe) é real mas **não é surpasse**; surpasse = `Δ > 0` com IC separado.

## O protocolo (3 braços, mesmos IDs, Docker oficial)
- **Tasks:** **só oficiais do SWE-Bench Pro** (instance_id ∈ 731), seleção determinística (`elevation_pro_suite_manifest.json`), held-out. **N suficiente pra IC** — 5 é subdimensionado pra cravar surpasse; **expanda N** (ex. 30–50) e reporte IC. Nada de synthetic, subset cherry-picked, nem Verified-carimbado-Pro (proveniência por `instance_id`, não por label).
- **3 braços, todos no mesmo conjunto de IDs:**
  - **A — DeepSeek sozinho** (sem atomic), congelado.
  - **B — DeepSeek + atomic** (substrato completo: guards de processo, navegação/WHERE, eliminação within-task, piso de byte).
  - **C — baseline frontier**, congelado, com recibo (`baseline_role=frontier`, `frozen=true`, `official_docker=true`, `dataset_name=ScaleAI/SWE-bench_Pro`, `task_ids` pareados).
- **Scoring:** Docker oficial do Pro (Modal), resolved/not, para os 3 braços.
- **Reporte:** `lift = B − A`, `Δ = B − C`, **por-task + agregado + IC (binomial/bootstrap)** + a **curva de lift vs acúmulo** (lift cresce conforme o corpus de processo cresce?).

## Guardas anti-fachada (inegociáveis)
- **Non-claim até o número fechar:** `metric_claim=false` enquanto não houver sample+Docker+recibo. `--verify-round-receipt <run>/round_receipt.json` tem que dar `round_receipt_ok=true` antes de QUALQUER linha de métrica.
- **Sem replay, sem vazamento de problem-statement, baseline congelado.** Zero contadores de falha/timeout no stream summary.
- **Paridade ≠ surpasse.** Reporte os três regimes honestos: `lift>0 IC-separado` = **atomic eleva o DeepSeek** (a prova que você pediu); `Δ>0 IC-separado` = **supera o frontier**; IC sobreposto = **paridade**; negativo = **não eleva** (registra igual, sem fingir).
- **Nunca finja verde, nunca fabrique número, nunca conte eficiência/within-task como Elevação.** Só via `expand_self`; não tocar driver co-dono se Codex vivo.

## Critério de sucesso (o que cada número significa)
- **`lift > 0` com IC separado** → **PROVADO: o atomic eleva o DeepSeek em Pro oficial.** (Resposta direta à pergunta. É o resultado bancável mesmo se não superar o frontier.)
- **`Δ > 0` com IC separado + margem crescendo com acúmulo** → **o fraco+atomic SUPERA o frontier** (a meta-estrela, por número).
- **`Δ ≈ 0`** → paridade em Pro (real, não a meta).
- **`lift ≈ 0` ou `< 0`** → o atomic **não eleva em Pro** — teto honesto, registra e para de inflar.

## Próximo passo exato
1. Rotacionar credenciais → exportar só por env → desarmar a mina de proveniência (qualquer `meta.json` Verified-carimbado-Pro fora do caminho).
2. `run_pro_elevation_round.sh --ready /tmp/proelev-ready.json` → exigir `ready_to_run=true`.
3. Rodar os **3 braços** (A/B/C) nos mesmos IDs Pro (N expandido), scoring Docker oficial.
4. `--verify-round-receipt` → `round_receipt_ok=true`; summaries `metric_claim=false` até verificados.
5. **Gravar no LEDGER:** `lift = B−A` (± IC, por-task), `Δ = B−C` (± IC), curva de lift vs acúmulo. **Esse é o número que decide o projeto inteiro.**

Sem número fresco no LEDGER, é deriva. Provado por número, jamais por desejo.
