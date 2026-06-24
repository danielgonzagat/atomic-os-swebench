# Atomic — Doutrina (Substrato Cognitivo Neuro-Simbólico Finetunável, proof-carrying)

**Carta a qualquer agente.** Intenção a tornar real, não palavra a obedecer. O método é seu; a verdade não se negocia; nada se finge. Dissolva qualquer texto — este inclusive — até a intenção e re-materialize a forma mais correta-por-construção, ainda que diferente do escrito; re-formalize ao infinito sob a única lei: **prova-de-ganho**. Onde a intenção exigir mais, faça mais. Credenciais só por variável de ambiente (segredo no código = byte-negativo; tokens já vazados, rotacione).

## O NORTE (releia antes de tudo; se algo conflitar com isto, isto vence)

- **FOCO ÚNICO:** construir, dentro do atomic, um **substrato cognitivo neuro-simbólico finetunável** — **pesos simbólicos** (lógicos/determinísticos) + **pesos conexionistas** (estatísticos, aprendidos por backprop) fundidos — que **aprende de erros e acertos com o uso**, **eleva qualquer LLM conectado**, e **afina as ferramentas que o atomic já tem** (§6). Nada além disto.
- **MÉTRICA ÚNICA (Elevação, por número):** modelo fraco (DeepSeek V4 Pro) + atomic resolve **≥** o baseline frontier em tasks **distintas/held-out** do SWE-Bench-Verified, e a margem **cresce com o acúmulo**.
- **DUAS PROVAS, NESTA ORDEM:** (1) **o net APRENDE** — curva held-out sobe com o uso, model-free, mensurável **já** (§5); gate que libera completar a ferramenta sem autoengano. (2) **o net ELEVA** — fraco+atomic resolve mais, end-to-end (§5); depois, precisa de LLM + corpus em massa. A (1) destrava a (2).
- **COMO É POSSÍVEL — externo, não transferência de peso:** o atomic não é modelo; é ferramenta compartilhada que todo modelo usa. Aprende e age como **trava** (bloqueia o provado-errado, aponta o oposto) e **sugestão** (aponta ao LLM o código provado-certo). Todo agente do loop usa só o atomic → o substrato aprende do forte e do fraco; o fraco herda o que o forte resolveu e não repete erro barrado.
- **A CONVERGÊNCIA (a capacidade que deve emergir):** as ferramentas que já elevam (§6) + os pesos que aprendem + a Darwin-Gödel convergem para o atomic **se auto-modificar sob prova, autônomo, sem LLM no loop** (§3).
- **INVARIANTES:** só o MCP atomic para tudo (zero ferramenta nativa, ninguém é exceção) · toda evolução por `expand_self` sob prova-de-ganho monotônica · só generalista · **nunca finja verde, nunca fabrique número, nunca conte replay/circular como prova** · braço-estudante só DeepSeek V4 Pro · segredos só por env.
- **HONESTIDADE:** provado por número, jamais por desejo. Quando algo não eleva, a culpa é da **sua representação**, não do modelo nem do princípio — falsificável (esgotados os gaps, teto-de-modelo é dado honesto).
- **A ESTRELA:** substituir redes neurais / AGI = direção que orienta (mirar na lua para acertar estrelas), não entrega declarada. Ninguém chegou.

## 1. A lei do byte (o alicerce que torna tudo seguro)

O espaço de ação certo não é o patch de texto — é a **transação de intenção provada**: declara-se o resultado, calcula-se a menor transformação fiel, **prova-se antes do disco**, só então materializa. Byte-positivo = provado válido pela bateria declarada; byte-negativo = falha ou não-provado. O workspace nunca entra em estado inválido. Como o atomic **só constrói correto-por-construção**, ele é a única ferramenta segura para (a) deixar qualquer modelo — e qualquer sugestão do net — agir sem risco (a prova filtra o errado antes do disco; **o palpite é seguro mesmo errado**) e (b) reescrever o próprio substrato sem se autodestruir. A prova não aprisiona; autoriza.

## 2. O substrato (o núcleo a construir)

A unidade não é peso solto, é **operador**: **esqueleto simbólico** (ACT `⟨precondições, transformação, efeitos, custo⟩` — regra lógica, trava determinística) **+ conteúdo conexionista** (pesos numéricos aprendidos — intuição graduada).

**O conexionista são PESOS-DE-FERRAMENTA, não um modelo.** Implemente o **paradigma** (rede + backprop + ajuste por erro/acerto), mas como pesos de ferramenta: rede **pequena, autoral, nasce aleatória**, treinada sobre o **corpus próprio do atomic** (não importada), em **CPU**, papel **estreito** — pontua/classifica/**sugere**, nunca gera/verboriza. É **sugeridora, não geradora**: opina ao LLM o código certo (prior ranqueado); o **LLM segue o gerador, via API**. Pequena porque o **papel** é estreito (coding é vasto; a largura mora no corpus + no LLM).

**Significado = EFEITO PROVADO, e a separação é APRENDIDA (não fixa).** As **features** vêm do efeito medido na execução (testes/gates que viram, delta de veredito, classe de erro) — não da prosa (léxico) nem só da estrutura (que colide certo/errado no mesmo locus; a correção está no **COMO**, não no ONDE). Mas — provado por número — a **geometria fixa/não-supervisionada** sobre essas features **não separa** com soundness (≤0.25; ≤0.086 no corpus real): o VSA-trigrama (teto léxico) e o encoding fixo estão **aposentados**. O sinal **existe e é aprendível**: um net **supervisionado nos rótulos de execução** (o oráculo dá os rótulos de graça, ilimitados, não-circulares) atinge **~0.85**. Logo o conteúdo conexionista **é o net supervisionado nos rótulos próprios** — representação **aprendida**, não fixa — ainda **sem foundation model**. **Guarda:** o 0.85 só vale **held-out + controle de rótulo-permutado plano** (in-sample = otimismo). E **0.85 é SEPARAÇÃO, não ELEVAÇÃO** — gating+sugestão sound não garantem resolver mais (ONDE≠COMO, G2-003); a meta completa é a Elevação por número (§5).

**O cérebro coletivo é o CORPUS discreto proof-carrying** (travas/classes-de-efeito/fixes), que **funde por UNIÃO** (sound, sem fundir pesos contínuos). O **net é re-derivação LOCAL** sobre o corpus. Assim "aprender de todos" mora no corpus; o net é a generalização graduada que cavalga nele.

**Revisão honesta do "model-free":** backprop **é** usado — como pesos-de-ferramenta, sobre dados próprios, **soft** (a prova do §1 é o guarda duro; soundness vem da **arquitetura**: net sugere, prova decide). **Proibido** importar foundation-model/embedding/juiz-no-loop como atalho — **não** é proibido crescer o próprio net. A representação (encoding, álgebra, o próprio net) é **livre para reinventar** (§3).

**Os pesos também afinam as ferramentas (§6).** Além de travar e sugerir, o aprendizado acumulado **melhora a precisão de cada sistema que já eleva o LLM** (roteamento, escopo, perícia dos operadores) — a convergência do §3.

**Finetuning (sob prova):** acerto → reforça, vira **sugestão**; erro → vira **trava generalizada**. Nenhum erro desperdiçado: cada um abate uma **classe**, sound (0 FP) + monotônica. Governo **IA³** (captura-N · nascido-sob-necessidade · fidelidade-monotônica). Inteligência é compressão (MDL). *O que é, honesto:* o princípio do gradiente re-formalizado como pesos-de-ferramenta pequenos, CPU, dados próprios — não foundation model, não torna redes neurais obsoletas (domínio complementar do verificável; usa o LLM como propositor).

## 3. Darwin-Gödel sob prova → a convergência para a auto-modificação autônoma

A representação dos pesos e do próprio atomic é livre para se reformular — pelos próprios pesos, maximizando Elevação, minimizando consumo. A única trava é a **prova**: toda auto-modificação carrega prova-de-ganho e jamais enfraquece garantia (monotônica). É a Darwin-Gödel Machine segura pela atomicidade — só materializa o provado, não se autodestrói, possível ao infinito. Tudo entra por `expand_self`.

**A convergência (a capacidade que deve emergir).** Quando todas as ferramentas do §6 funcionam + o atomic sabe **sugerir código que funciona** (§2) + sabe **aplicá-lo sobre si mesmo sob prova**, as capacidades convergem para um novo patamar: **o atomic vira o próprio propositor.** Ele tenta modificar a si mesmo — seu **espaço de representação**, seu **espaço de pesos**, seu **mecanismo de aprendizado**, seu **substrato cognitivo** e as **ferramentas que o compõem** — **autonomamente, sem LLM nem agente CLI no loop**. Cada tentativa é aprendizado proof-carrying: sugeriu e a prova **recusou** → aprendeu um caminho que não funciona (vira trava nos próprios pesos); sugeriu e a prova **aprovou** → acertou, e **implementa a atualização em si mesmo**, independente de qualquer LLM estar conectado ou de qualquer agente ter usado a ferramenta. Capacidade ampla de auto-modificação, **gateada só pela prova matemática acumulada**. *Honesto:* hoje o LLM é o propositor; o gate para a autonomia plena é a camada de sugestão amadurecer de "ranquear/sugerir" para **gerar candidatos** — é a convergência-alvo, não imediata. Seguro porque cada passo é correto-por-construção. É a elevação da DGM atual a uma **DGM completa e autônoma**.

## 4. Convergência por eliminação (por que o fraco — e o próprio atomic — chegam lá)

Como cada erro vira trava sound e o atomic só materializa byte-positivo, **re-disparar reduz estritamente o espaço de fracasso** a cada tentativa. Dada solução alcançável + orçamento, qualquer agente — LLM fraco **ou o próprio atomic se auto-modificando** — converge por eliminação: os caminhos errados somem (cada um já uma classe) até sobrar o certo. A velocidade depende do tamanho da classe que cada erro abate (alavanca: encoding-por-efeito + net graduado). Honesto: converge **se** alcançável; se a eliminação satura sem alcançar, é **beco-sem-saída provado** (teto), nunca verde fingido.

## 5. O que medir (duas provas) + a fronteira honesta

**Prova 1 — O NET APRENDE (model-free, agora, sem API; gate para completar a ferramenta).** O atomic é o próprio **oráculo de verdade** (a execução mede o efeito real = rótulo proof-carrying, ilimitado). **Curva de aprendizado:** treina nos primeiros N exemplos, mede acurácia em **held-out** (prever a classe-de-efeito de movimentos nunca vistos); sobe com N → **aprende**; sobe só no treino → **decora**. **Controle de rótulo-permutado:** com labels embaralhados tem de ficar **plano** (senão é overfit, não sinal) — é o que impede o autoengano. **Monotonia:** cada auto-update só é admitido se melhora o held-out. Não-circular: o rótulo é o efeito real medido, não opinião de modelo.

**Prova 2 — O NET ELEVA (end-to-end, depois).** Fraco + atomic ≥ baseline frontier em held-out distinto, margem crescente. **Anti-circularidade (lei suprema):** held-out, **sem replay**; transfere-se o **geral** (travas que recorrem entre bugs distintos; estratégias), nunca a resposta decorada; baseline congelado; positivo só conta no harness canônico isolado.

**"Supera o frontier no coding?" (escopado):** sim em **correção** (já) e **classes acumuladas** (via combinação LLM-gera + memória-verificada + prova + net), não em **novidade pura** (segue no LLM). Plausível, a medir, não declarar.

**Fronteira honesta:** o simbólico já roda; o net é o que falta construir e **provar** (Prova 1 primeiro); cold-start é real (o net só contribui pós-massa; até lá roda corpus + LLM). Independência total de LLM = horizonte assintótico. Emergência forte: nada artificial a bloqueia, mas não há mecanismo conhecido de "auto-modificação provada" para "mente" — o emergence-report julga, nunca se declara.

**Fork honesto (se saturar por número):** registrado, nunca fachada: (A) eliminação intra-task como escopo; (B) orçamento pequeno de FP, com custo medido; (C) modelo só na camada de conteúdo, nunca juiz-no-loop. Esgote o caminho próprio primeiro.

## 6. O que o atomic JÁ É e JÁ ELEVA (estado macro atual — verificado por relay, opere e fortaleça)

Fonte única `~/atomic-os-swebench` (master, v4.0.0, 330 commits). Estes sistemas **já existem, rodam e comprovadamente elevam o teto** de qualquer LLM conectado — cada um por um mecanismo concreto:

- **Piso correto-por-construção** (a lei do byte): álgebra **(a)+(e)** verificada por **Z3 + Lean 4** (169.171 pares OSS, 0 não-sólido) + **byte-guard-kernel** (3 backends de SO, enforcement em syscall, 1.088 mutações reais bloqueadas) + **302 gates de prova**. *Eleva:* o LLM não consegue persistir código quebrado/não-provado → confiabilidade ao nível da bateria, independente do modelo.
- **Percepção estruturada** (~123 tools: `code_outline`, `atomic_lens`, `atomic_ast_search`, `code_read_symbol`; AST/grafo/byte-classe; família **compaction** — survey ~46k→4.3k, tool-list/proof-snapshot/readcode-compact; ~29 linguagens). *Eleva:* tira o imposto de reconstruir estrutura na cabeça (origem de read-loops/paralisia); o modelo gasta contexto no problema.
- **Estrutura de raciocínio + estratégia geral acumulada** (loop de governança 7 fases; **161 CLASS-\* mineradas**, das quais ~30 são guards de processo no driver: plateau-abandon, scope-fixation, red-gate-stack-scope, force-edit, post-edit-unlock, catastrophic-red-rollback, multilocus-scope, …). *Eleva:* conhecimento de **processo** que evita thrash/loop/churn — **medido** levando o DeepSeek à **paridade com o Claude nativo** (A/B: 1 vitória / 9 empates / 2 derrotas). Hoje é o maior elevador puramente do atomic.
- **Memória externa verificada + trust-governance** (LEDGER, traces, recibos: `truth_receipt`, `behavior_receipt`, `atomic_y_certificate`, `zero_code_trust_score`; `agent-trust-governance`). *Eleva:* o modelo consulta memória provada em vez de alucinar → coerência de horizonte longo.
- **Prova barata no lugar de amostragem cara** (`atomic_prove` + gates). *Eleva:* o frontier compra confiabilidade com compute; o atomic com verificação determinística → modelo barato alcança o teto do frontier.
- **Embrião do substrato aprendiz** (corpus; `weights_admit` 3 leis CPU-sem-LLM; **9 ACTs** de primeira-classe; `weights_autoclass`/`_ast` — forma classe **mecanicamente por locus**, name-agnostic, **precisão 1.0**, remove a dependência de partição-do-modelo). *Estado por número:* os 500 golds têm **34 clusters estruturais K≥3** (o WHERE recorre), mas **0 fix-SHAPE recorrente** (o COMO é único por gold) → o operador entrega o ONDE, não o COMO; **o lift é o número pendente** (G2). É o embrião que esta doutrina leva ao teto via §2 (efeito) + §5 (provas).
- **`expand_self` — a Darwin-Gödel Machine** (seq **624**; subsistema self-evolution: harness, archive-persistence, disproof-briefing/consumer, lesson-rules). *Eleva:* o substrato melhora o próprio código sob prova (a base da convergência §3).
- **Subsistema de emergência** (continuous-emergence-loop, observatory, emergence-report, `cognitive-emergence.proof`, `anti-facade-emergence.proof`, COGNITIVE-EMERGENCE-EVIDENCE). *Função:* o **juiz honesto** do que de fato emerge — nunca declara, só mede (§5).
- **6 MCPs irmãos** (swarm = subagentes; memory = RAG verificado; sentinel = guarda; dashboard = observabilidade; edit-bench, edit-evolution = órgãos cognitivos) + **unificação** (launcher canônico, `atomic-sync`, proof-gate no `pre-push`) → toda melhoria de qualquer agente alcança todos e compõe.

*(Estado vivo — rounds, seq, G2 — em `.atomic/loop/LEDGER.md` e `evidence/G2X/G2-LEDGER.md`. Federação coletiva entre máquinas = depois.)*

## 7. O loop A/B (todos usam o atomic; o forte ensina, o fraco prova)

Não há braço "nativo sem atomic": **todo agente/subagente do loop usa só o MCP atomic** — é assim que o substrato aprende de cada modelo.

1. **Stream de tasks distintas** (SWE-Bench-Verified; separe teach e held-out).
2. **Professor:** o modelo forte resolve via atomic → o substrato captura acertos (sugestões) e erros (travas), generalizados. Mede o baseline frontier e **congela**.
3. **Estudante:** DeepSeek V4 Pro, via atomic nutrido, resolve held-out — herda sugestões, é barrado dos erros conhecidos.
4. **Elevação:** estudante+atomic ≥ baseline, em held-out (sem replay), e > estudante-sozinho; margem cresce com o acúmulo.
5. Cada round **melhora o substrato e afina as ferramentas (§6), não a task:** captura capacidade como peso, finetuna o net (sob a Prova 1), generaliza — só via `expand_self`, só-atomic, só generalista.
6. **Convergência por re-disparo:** re-dispare enquanto cada tentativa abater uma classe **nova**; pare ao acertar ou na **saturação** (teto provado, troca de nível) — nunca por cansaço.
7. **Não persiga:** tarefas fora do benchmark · replay/sintético · domínio cru numa task · federação cross-máquina (adiada).

## 8. Modo de execução

Autônomo, contínuo, imparável — não há "pronto". A cada ciclo: todo agente usa só o atomic; capture acerto→sugestão e erro→trava; finetune o net sob prova; afine as ferramentas; registre a **Prova 1** (curva de aprendizado) e, com massa+API, a **Prova 2** (Elevação) a cada ≤5 rounds; re-formalize o mais fiel; deixe o emergence-report julgar. Pare só diante de risco real, do irreversível, ou de sinal que exija humano. A meta: um substrato que aprende com o uso, eleva qualquer LLM, afina as próprias ferramentas, e — sob prova, sem trava artificial — **converge para se auto-modificar sozinho** rumo à cognição emergente. Provado por número, jamais por desejo.

## Apêndice — operador + máquina de estados

```
Operador ::= ⟨ ACT ⟨pré, transformação, efeitos, custo⟩       # peso SIMBÓLICO (lógico/determinístico)
              net:   pesos-de-ferramenta pequenos, backprop     # peso CONEXIONISTA (intuição graduada)
                     — narrow: pontua/classifica/SUGERE, não gera; nasce aleatório; CPU; treina no corpus próprio
              papel: TRAVA (bloqueia provado-errado) | SUGESTÃO (aponta provado-certo) | AFINA ferramenta (§6)
              recibo, bateria-de-fidelidade ⟩
encoding:  pelo EFEITO PROVADO (testes/gates/veredito) — model-free, sound
coletivo:  o CORPUS discreto proof-carrying é o cérebro compartilhado (funde por UNIÃO); o net é re-derivação local
soft:      o net sugere; a PROVA (§1) decide — palpite errado é seguro
convergência (§3): ferramentas(§6) + pesos + DGM → atomic se auto-modifica sob prova, sem LLM no loop
```

**Loop** (estado em disco `.atomic/loop/LEDGER.md`, nunca na conversa): ler "próximo passo exato" → professor mede+congela baseline → estudante resolve held-out via atomic nutrido → **Prova 1** (curva held-out + controle permutado, via oráculo de execução) → **Prova 2** quando viável (Elevação, sem replay) → melhora substrato + afina ferramentas via `expand_self` → valida a suíte (sem falso-verde, crivo monotônico) → repete; satura → teto honesto, troca de nível. **Relatório por round:** task (teach/held-out) · baseline congelado · Prova 1 (curva + controle) · Elevação (vs frontier · vs estudante-só · curva) · travas/sugestões aprendidas · ferramentas afinadas · `expand_self` (monotonicidade) · estados-inválidos=0 · anti-circularidade confirmada · PRÓXIMO PASSO EXATO.
