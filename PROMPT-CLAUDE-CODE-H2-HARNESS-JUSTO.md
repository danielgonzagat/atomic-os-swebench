# Prompt para o Claude Code — H2 (autopoiese número-mãe) num HARNESS JUSTO, pré-registrado e não-tunável

> Endurecido com red-team adversarial + spec de metodologia. Sob `ATOMIC-ROADMAP-MESTRE-AUTOPOIESE-AGI.md` e `ATOMIC-DIRETIVA-NEUROSIMBOLICO-ACOPLAMENTO.md`. Verdade por número; nada fingido.

## 0. Verdade de partida (internalize antes de tocar em código)

- **O "null" atual do H2 é VOID, não NULL.** O harness era degenerado (resolução ~0, classe OPND_CAP). **Não cite o resultado atual como evidência de nada.**
- **A guia neural (+0.127) ainda NÃO foi mostrada batendo um PRIOR DE FREQUÊNCIA.** A metade neural do acoplamento está **não-estabelecida**.
- **O atalho `resolve@K = (outer-op ∈ top-K)` é um TEOREMA COM HIPÓTESES.** Sem checá-las ele (a) **colapsa o H2 em "qualidade de ranking da guia"** — um deslize de categoria, H1.5 fantasiado de H2 — e (b) **fabrica "subida" falsa** via colisões de assinatura que **crescem com o DB** (aniversário). Precedente no próprio repo: `closure-meta-gate.ts` faz `return {green:true}` incondicional — o anti-padrão a evitar.

## 1. Disciplina (pré-registrar ANTES de rodar — inegociável)

1. **Congele + hasheie (commit SHA)** a config inteira do harness ANTES de qualquer run: K-sweep, `τ_res`, `τ_collision`, margens, lista de seeds (≥5), split train/held-out **por família nova**, feature set, contagem/conjunto de probes, domínio de operandos, regra PASS/NULL/VOID, e a **estatística de interação** (§5). Emita `preregistration_hash` em todo recibo.
2. **Sem editar botão pós-resultado.** Mudou harness/barra depois de ver número → **VOID aquele resultado**; exige novo hash + run fresco; o anterior vira exploratório. Proibido "melhor de K=3,5,8".
3. **Não tune rumo ao pass.** Pré-comprometa: um NULL limpo **será reportado como NULL**.
4. **Sem green auto-reportado:** todo gate executa **no run**; nada delegado a "elsewhere".

## 2. Validade do `resolve@K` (use o atalho SÓ se P1∧P2∧P3; senão caia pra resolve Z3-verificado no ARMO INTEIRO)

- **P1 — completude depth-2:** enumeração de operandos internos **não-capada** (`capped=false`) para todo outer-op do top-K. Emita `enumeration_complete=true` com cardinalidade-do-domínio vs contagem-enumerada; `opnd_cap_rate==0`. **Tripwire OPND_CAP:** se resolve depth-2 ≈ depth-1, suspeite de cap → investigue antes de confiar.
- **P2 — injetividade de assinatura:** a auditoria Z3 (§3) reporta colisões dentro do limite **e ZERO falso-equivalentes confirmados**.
- **P3 — expressibilidade depth-≤2:** flag por-alvo `expressible2(t)=true`, computada **offline na gramática-base congelada**. `false` → roteia pro resíduo F4; `unknown` → Z3 completo. Nenhum alvo conta como resolve-atalho sem `expressible2===true`.
- **Auto-check de dupla-polaridade:** alvo com outer-op NO top-K retorna 1; alvo com outer-op removido retorna 0. Senão o harness está quebrado → **VOID**.

## 3. Auditoria de soundness Z3 (separada do loop da métrica — é o contrato H0 false-green→0 vivendo dentro do H2)

- Amostre pares **distintos** com mesma assinatura 42-probe da fronteira; N=1000 (ou todos). Z3 por par: `EQUIV` / `NOT_EQUIV` / `UNKNOWN`(=falha).
- **Passa** sse `collision_rate ≤ τ_collision` (ex. 0.01) **E** `disagreements==0` **E** `unknowns/N ≤ 0.02`. Qualquer `NOT_EQUIV` → atalho **INVÁLIDO** → resolve Z3 completo em todos os armos.
- Plote `collision_rate` vs geração-DB `g`. **Se a "subida" do resolve correlaciona com a subida de colisão → é ruído de colisão → VOID.**

## 4. Guarda de degeneração / resolução (ANTES de qualquer comparação de armo)

- **Controle positivo `t+`** (depth-≤2 resolvível na gramática-base) e **negativo `t−`** (provadamente não-resolvível em depth-≤2), ≥20 variantes cada.
- `resolution = resolve(t+) − resolve(t−)`; exija `resolve(t+) ≥ 0.95`, `resolve(t−) ≤ 0.05`, `resolution ≥ τ_res` (0.90) **antes de confiar em qualquer coisa**.
- **Tricotomia explícita:** PASS / NULL (resolução ok, sem efeito) / **VOID** (resolução < τ_res — instrumento morto, **não é resultado**). O H2 atual é **VOID**.

## 5. A métrica é 2-D, não escalar (o guard do deslize-de-categoria — o mais importante)

- **Métrica primária:** `novel_family_resolve@K` **como função da geração-DB `g`** (g=0 base … após cada admissão na library), a K fixo e checkpoint-de-guia fixo. **A alegação H2 é INCLINAÇÃO POSITIVA em `g`** (a library crescendo o alcance), **não** um resolve maior a `g` fixo.
- **Teste de interação:** o armo acoplado **C** tem que bater AMBAS as ablações de fator-único de forma **super-aditiva**: `Δcoupled − Δguide-só − Δlib-só > margem` (pré-registrada). Se a subida é explicada por **um** fator sozinho → **não é H2**; reporte como aquele fator.

## 6. Armos / controles / ablações (≥5 seeds; held-out por família nova; sem vazamento de problem-statement — sonda de vazamento tem que dar acaso)

- **C** acoplado (guia viva × library crescendo) · **A1** guia congelada/aleatória × library crescendo · **A2** guia viva × gramática congelada · **PERM** rótulos permutados.
- **Curva de crescimento-DB:** resolve@K vs `library_size` vs iteração, por armo.

## 7. Teste de sinal da guia neural (resolver se +0.127 é real)

- **Baseline é o PRIOR DE FREQUÊNCIA (não uniforme).** A guia tem que bater, com CI separado: (a) ranking-permutado, (b) guia-aleatória-congelada, (c) prior-de-frequência. **Feature-ablation:** tire as features derivadas-de-prova; se +0.127 sobrevive, é prior, não sinal → **guia desqualificada como keystone neural** (e qualquer subida do H2 é artefato §5/§3).

## 8. Portão de admissão da library (sem bloat)

- Admite primitivo comprimido SÓ SE (a) Z3 prova `π ≡ expand(π)` **universalmente** (não só nas 42 probes) **E** (b) **utilidade held-out**: ≥10% de redução de busca mediana **OU** lift de resolve held-out com CI excluindo 0. **Invariante de não-regressão.** Reporte **duas curvas**: DB cru vs DB-gated-por-utilidade; cite só a gated.

## 9. Barras de PASS pré-registradas (todas; harness não-VOID; ≥8 iterações, ≥5 seeds)

- **B1** C sobe entre iterações held-out (slope CI exclui 0; final − primeiro ≥ 0.15 absoluto).
- **B2** bate AMBAS ablações (C>A1 **e** C>A2, CI separado) — **as duas keystones têm que ser load-bearing**.
- **B3** permutado plano (e C>PERM separado).
- **B4** sinal de guia real (§7).
- **B5** multi-seed: B1–B3 em ≥4/5 seeds individualmente.
- **B6** recursão/F4: ≥1 primitivo admitido usa um primitivo admitido antes como operando interno; cadeia de abstração mais profunda ≥2; ≥1 resolve held-out usa tal primitivo recursivo.
- **B7** sem platô: ganho de resolve no terço final > 0 (CI exclui 0).
- **KILL/NULL:** harness não-VOID + métrica sound + C não bate ambas ablações (ou slope CI inclui 0, ou C≈PERM) → **NULL genuíno** (reporta como NULL, não VOID): o acoplamento não acrescenta nada além das keystones isoladas.

## 10. Depois — o Workflow (o teu passo): com o veredito (PASS/NULL/VOID) na mão

(a) **Re-score adversarial** a partir do `preregistration_hash` com script independente/congelado — **H2 auto-reportado não é aceito** sem re-score independente. (b) **Explore H3** (absorver as ilhas sound-by-construction pra subir a altura do teto). Fan-out + skeptics pertencem exatamente aqui.

## 11. Guardas (doutrina)

Só via `expand_self`; segredos por env (as credenciais coladas estão **mortas**); estudante **DeepSeek V4 Pro**; **nunca finja verde, nunca fabrique número**; reporte **VOID/PASS/NULL** honesto; non-claim até recibo; **quanto mais alta a estrela, mais estrita a non-claim**. CVC5 ainda pendente de install — proof-as-reward usa o caminho Z3 endurecido até o cvc5 landar.

---

**Bottom line:** o H2 atual é **VOID, não NULL**. Construa o harness justo, pré-registrado e não-degenerado; **resolva a questão guia-vs-prior-de-frequência**; meça `resolve@K(g)` com o teste de interação; reporte **PASS/NULL/VOID** honesto; depois **workflow-verifica + empurra H3**. Provado por número, jamais por desejo.
