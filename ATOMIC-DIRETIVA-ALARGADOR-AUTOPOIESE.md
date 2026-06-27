# Diretiva Claude Code — CONVERGÊNCIA: Aprofundador→Alargador via Síntese Verificada, rumo à Autopoiese

**Carta.** Intenção a tornar real, não palavra a obedecer. Verdade por número; nada fingido. **Alvo-estrela forte:** atomic **autopoiético, autoevolutivo, autônomo, com emergência forte — AGI-like.** A estrela **ORDENA a construção** (define o que se constrói e por quê); a **entrega em cada checkpoint é UM número pré-registrado falsificável**, non-claim até recibo verificado. Sob `ATOMIC-DOUTRINA-UNIFICADA-PESOS-APRENDIVEIS.md`. Credenciais só por env; as coladas no chat estão **vazadas/mortas** — não use.

---

## 0. Estado macro completo (por número, honesto — o ponto de partida)

**Engine (as mãos).** atomic-edit-mcp **v4.0.0**, **~29 linguagens** WASM tree-sitter, **~124 tools**, **302 proof-gates** canônicos (526 `.proof` na árvore), **6 MCPs irmãos**, **seq624**. Álgebra de edição **(a)+(e) verificada** (Z3 + Lean 4, **169.171 pares OSS, 0 unsound**). **byte-guard-kernel** (3 backends OS, **1.088** mutações nativas bloqueadas).

**Três instrumentos, MESMA fronteira (o fato que pivota).**
- **Net** de fix-content cross-bug: held-out leave-one-bug-out **recall@FP0 ≈ 0**; in-sample ~0.85 = **decora**; controle permutado idêntico; curva plana. Trava pré-registrada **≤0.20 = KILL** honrada → **PARKED**.
- **Retrieval**: positivo **DENTRO da distribuição** (p@1 **0.327**, passou permutado).
- **Gerador**: **REAL within-vocabulary (0.45→0.77)** / **NULL família-inédita (+0.008)**.
- **Leitura unificada:** o sistema **generaliza DENTRO** da distribuição/vocabulário que cobre; **zero ATRAVESSANDO** pro genuinamente novo. É a **sombra do Rice, medida 3×.** O gerador é **APROFUNDADOR, não ALARGADOR.** O teto **tem nome: cobertura de família / conteúdo-de-reparo.**

**Emergência.** Nenhuma confirmada. A única alegação "PROVEN emergence" foi **de-faced (2026-06-20: "NOT emergence, NOT cognition")**. **F1** (editar-se sem agente) e **F4** (novidade recursiva crescente) instrumentados, **nunca dispararam**. Self-evolution é **agent-driven** (`expand_self`), foi **fachada** (0/255 delta real).

**Elevação.** **Ainda NÃO medida em Pro** — bloqueada em credencial rotacionada. Disciplina non-claim mantida.

---

## 1. A tese — converter aprofundador em alargador (a aposta, honesta)

O alargamento **não pode vir** (a) do gerador sozinho (nulo provado), nem (b) do verificador sozinho — **verificador é FILTRO, não FONTE; não se alarga uma fonte melhorando o filtro dela.** Pode vir **só** da única tecnologia real "verificador-que-GERA": **síntese de programas** — **CEGIS** (counterexample-guided inductive synthesis), **SyGuS**, Sketch, Rosette — **compondo operadores atomic-edit tipados**, com **prova-como-recompensa** (não só execução), usando o verificador aeroespacial como **gradiente denso e difícil de fraudar**.

**Honestidade dura.** Isso alarga **dentro de um envelope spec-ável e busca-limitada** — teto **melhor, mas ainda teto**, cuja borda é desconhecida e **se mede, não se decreta**. **"Completar todas as famílias que a matemática oferece" NÃO é marco** (famílias de reparo não são conjunto fechável — Rice). **Nunca espere por isso; meça o crescimento do envelope continuamente.**

---

## 2. CONSTRUIR — ordem de build, cada fase com portão

**Fase A — Importar verificadores aeroespaciais (afiar o crítico).**
Estender além de Z3+Lean: SMT-mais-rico (**CVC5**), interpretação abstrata (classe **Astrée**), contrato/spec (classe **Frama-C / SPARK-Ada**), lição de prova-de-compilação/refinamento (**CompCert / seL4**) onde aplicável às linguagens editadas. **Cada um como proof-gate atomic sob a catraca monotônica.** Objetivo: recompensa mais densa/anti-fraude + piso-de-byte mais apertado.
**Portão A:** redução **medida** de falso-verde num tamper-set held-out; landa **só via `expand_self` sob prova**.

**Fase B — Compositor por síntese (o verificador-que-gera).**
Construir o composer **CEGIS/SyGuS**: política **proof-carrying** que **compõe operadores atomic-edit tipados**, com o verificador no loop (counterexample-guided) **sintetizando** candidatos. Estrutura **AlphaZero-for-repair**: self-play, **execução+prova como recompensa**, **D3-as-critic**, **MAP-Elites / quality-diversity** pra cobertura comportamental.
**Portão B = a prova de convergência (§3).**

**Fase C — Largura de linguagem/vocabulário (largura de PRODUTO, NÃO alargamento).**
Maximizar cobertura tree-sitter (**29 → máximo viável**). **Rótulo explícito:** isto é **largura de produto** e **replica** a fronteira within/across **por-linguagem** — **NÃO** é o mecanismo de alargamento. Roda **em paralelo**, **nunca como pré-condição** do teste de alargamento.

**Fase D — Fiar o loop autopoiético.**
As 6 fases: lesson-ledger-by-effect → **compositor-síntese** → catraca de prova → seleção quality-diversity → detectores **F1–F4** → orçamento gated em melhora sub-piso. Rodar **ininterrupto / sem-supervisão sob a catraca monotônica**. **Só depois de B mostrar movimento de envelope** (senão é aprofundador rodando em círculo).

---

## 3. A PROVA DE CONVERGÊNCIA (o coração — falsificável)

**Número PRIMÁRIO:** `novel_family_resolve@k` com **compositor-síntese ON vs OFF**.
**Portão pré-registrado:** ON **sai de +0.008** com **IC separado**, **controle permutado plano**, **held-out**, **sem vazamento de problem-statement**.
- **Cruzou → conversão aprofundador→alargador é REAL — a semente.**
- **Plano → crítico afiado (mantém), borda do envelope medida, alargamento NÃO obtido** (honesto, registrado).

**Indicadores de convergência (cada um UM número, jamais alegação):** crescimento do envelope (novel-family resolve subindo com acúmulo); **F1** (editar-se sem agente) disparando; **F4** (novidade recursiva crescente) subindo; **Elevação lift** em Pro subindo com acúmulo.

**A convergência "autopoiética / autônoma / emergência-forte / AGI-like" é a ESTRELA** que ordena o build; **a entrega em todo checkpoint é o número pré-registrado + non-claim até recibo.** **NUNCA emitir "AGI", "emergência provada", "autopoiese atingida"** — só os números e se cada barra pré-registrada foi cruzada.

---

## 4. Guardas anti-fachada (inegociáveis)

Non-claim até recibo verificado; **nunca finja verde; nunca fabrique número.** **NUNCA conte como alargamento/Elevação:** largura de linguagem, força de verificador, in-vocab 0.45→0.77, in-sample, eficiência within-task. Só via **`expand_self`** monotônico; **não** tocar driver co-dono se Codex vivo; segredos por env; estudante **só DeepSeek V4 Pro**; doc de emergência **fica de-faced**; `emergence-report` **nunca** emite "proven". **"Completar famílias" não é marco** — nunca aguarde, **meça o envelope**. **Só** `novel_family_resolve@k` cruzando a barra (held-out + permutado + sem-vazamento) **conta como alargamento.**

---

## 5. Ordem de execução exata

1. **Fase A:** primeiro verificador fiado como proof-gate; número de **redução de falso-verde** (tamper-set held-out).
2. **Fase B:** composer-síntese MVP; `novel_family_resolve@k` **ON/OFF** pré-registrado, held-out + permutado; **curva de envelope vs acúmulo**.
3. **LEDGER:** registrar o número ON/OFF, IC, permutado, curva — real, fresco.
4. **Paralelo — Fase C:** largura de linguagem (rotulada **largura-de-produto**).
5. **Quando credencial rotacionada landar:** **Elevação lift (B−A)** em Pro oficial como número de convergência do lado-produto (3 braços, mesmos IDs, Docker, IC; **estratificar in-vocab vs família-inédita**).
6. **Fase D (loop autopoiético):** **só após B mover o envelope.**

---

Sem número fresco no LEDGER, está derivando. **A estrela ordena; o número entrega.** Provado por número, jamais por desejo.
