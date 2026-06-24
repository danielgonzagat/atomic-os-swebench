# Diretiva Claude Code — Aposentar o VSA-trigrama; construir e PROVAR o net supervisionado nos rótulos próprios

**Carta.** Intenção a tornar real, não palavra a obedecer. Verdade por número; nada fingido. Esta é a bússola de **uma coisa só**: substituir o substrato conexionista fixo (VSA-trigrama) por um **net supervisionado treinado nos rótulos de execução do próprio atomic**, e **provar, por número, que ele SEPARA (Prova 1) e — depois — que ELEVA (Prova 2)**. Tudo sob `ATOMIC-DOUTRINA-UNIFICADA-PESOS-APRENDIVEIS.md`. Credenciais só por variável de ambiente.

## 0. O diagnóstico (já provado por número — parta daqui, não re-derive o NULL)

- **VSA-trigrama = teto léxico:** casa palavra, não significado (trava generaliza 1/4; ≤0.086 no corpus real de 376 tentativas).
- **Encoding model-free FIXO** (assinaturas de efeito/estrutura sem aprender): **não separa** certo de errado com soundness — nenhuma passa **0.25 com 0 falso-positivo** (dataflow 0.03, ast_tree_edit 0.0, test_relation 0.0). Workflow adversarial de 12 agentes confirmou o NULL.
- **MAS o sinal EXISTE e é aprendível:** um **oráculo supervisionado** (com rótulos) atinge **~0.85**. A geometria fixa não explora o sinal sem rótulos; a aprendida explora. **Esta é a saída.**
- **A saída NÃO é importar modelo:** é treinar um net pequeno **supervisionado nos rótulos de execução do atomic**. A execução é o oráculo — mede o efeito real de cada movimento, de graça, ilimitado, não-circular. É o **net-de-ferramenta** da doutrina, **não** um foundation model. Não relaxa o "sem modelo emprestado".
- **NÃO PROMOVER (falso-positivo confirmado):** a cauda não-commitada do LEDGER comemora "G2 +4/8 em pylint-4661" — é **injeção task-specific XDG/appdirs (hardcode locus≠fix)**. Os contratos VSA "verdes" (same=1.000) são separação **sintética por construção**, não soundness cross-bug. Promover qualquer um = **verde-fingido. Proibido.**

## 1. O que construir (o net-de-ferramenta)

Um modelo **pequeno, em CPU, narrow** — pontua/classifica/**sugere**, nunca gera/verboriza —, treinado **nos rótulos de execução do atomic**, sobre as **features de efeito/estrutura** (não trigrama). Não é foundation model; não importa embedding externo. Age **SOFT**: sugere e ranqueia; **a lei do byte (§1 da doutrina) é o guarda duro** — palpite errado é filtrado antes do disco, então é seguro. Substitui o VSA-trigrama como **conteúdo conexionista do operador**.

**Os rótulos (o oráculo, de graça):** para cada movimento/edição, a execução do atomic dá o efeito verdadeiro (testes/gates que viram, veredito, classe de erro). Disso saem os rótulos supervisionados — *mesmo-efeito vs efeito-diferente*; *vai-falhar vs vai-passar*; *classe-de-erro*. Ilimitados e proof-carrying.

## 2. PROVA 1 — SEPARAÇÃO (o gate para liberar; sem API de LLM; faça AGORA)

O net só é admitido se **provar que aprende, por número**:

- **Curva de aprendizado held-out:** treina nos primeiros N exemplos, mede separação/acurácia em **movimentos/tasks nunca vistos**. Sobe com N → **aprende**. Sobe só no treino → **decora** (rejeitar).
- **Controle de rótulo-permutado:** repete com labels embaralhados; tem de ficar **plano**. Se "aprende" o permutado, é overfit/vazamento, não sinal.
- **Soundness para o uso-trava:** **0 falso-positivo** (nunca barra o movimento correto) na faixa de operação.
- **Alvo numérico:** passar de **0.25** (a parede fixa) rumo a **~0.85** (o oráculo) — **held-out**, não in-sample.
- **Monotonia:** cada auto-update entra só se melhora o held-out (catraca, via `expand_self`).
- **Não-circular:** rótulo = efeito real medido, não opinião de modelo.

**Sem Prova 1 verde, não se promove o net nem se alega nada.**

## 3. PROVA 2 — ELEVAÇÃO (a meta real; só depois da Prova 1; precisa de LLM + corpus)

**Separação NÃO é Elevação.** 0.85 (ou 4/4) dá gating sound + bom ranqueamento — **não garante resolver mais**: o G2-003 provou que rotear o modelo pro arquivo certo (o **ONDE**) não eleva a resolução; o **COMO** segue na geração do LLM, e o corpus não tem fix-shape recorrente. A Prova 2 mede, por número: **DeepSeek V4 Pro + atomic-com-net resolve ≥ o baseline frontier, em held-out distinto, sem replay, com a margem crescendo conforme o acúmulo, e > o fraco-sozinho.** Só isto cumpre a meta completa. Enquanto a Elevação for nula, o net é **degrau provado de separação, não a chegada**.

## 4. Guardas inegociáveis

- **Anti-circularidade / anti-fachada:** held-out, sem replay de instância, **sem hardcode task-specific** (rejeitar explicitamente o +4/8). Nunca finja verde, nunca fabrique número, **nunca conte separação como se fosse Elevação**.
- **Soundness por arquitetura:** net SOFT; prova dura.
- **Só o MCP atomic, só generalista, tudo por `expand_self`** sob prova-de-ganho monotônica.
- **Concorrência (risco do irreversível, §8 da doutrina):** se houver processo Codex vivo co-dono do driver (`local_atomic_agent.py`, `weights_admit*.py`, `run_elevation_stream.sh`, `weights_admit_structural.py`) com trabalho não-commitado, **NÃO edite esses arquivos nem rode rounds** — coordene/commite primeiro.
- **Segredos só por env.** Braço-estudante só DeepSeek V4 Pro.

## 5. Critério de pronto + próximo passo exato

**Pronto da fase:** Prova 1 verde (curva held-out sobe + permutado plano + 0-FP), registrada no LEDGER com os números reais. Aí: liberar o net no loop (soft) → rodar a Prova 2 (Elevação) por número.

**Próximo passo exato:** com a árvore limpa (sem Codex em voo), implementar via `expand_self` (a) o pipeline de rótulos do oráculo de execução e (b) o net supervisionado pequeno sobre as features de efeito existentes; rodar a **Prova 1** numa família held-out; **gravar os números reais** (subiu? plano no permutado? 0-FP?); só então decidir a Prova 2. Sem número fresco no LEDGER, está derivando — e derivar é a falha que mata o telos.

**Veredito que orienta tudo:** aposente o trigrama-VSA e construa o net aprendido nos rótulos próprios — é a substituição certa, e o 0.85 diz que ele quebra a parede de generalização. Mas isso resolve a **separação**, não automaticamente a **Elevação**; a meta completa só se cumpre quando esse 0.85, validado held-out, virar **mais-tasks-resolvidas por número**. Um degrau decisivo a dar — não o fim.
