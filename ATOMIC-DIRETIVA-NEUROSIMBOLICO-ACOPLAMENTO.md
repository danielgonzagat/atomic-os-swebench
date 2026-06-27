# ATOMIC — Diretiva: O Acoplamento Neuro-Simbólico (as DUAS keystones) — ressuscitar a net no papel certo

**Carta.** A intenção, literal: um **loop autopoiético neuro-simbólico** — **redes neurais REAIS + simbólico REAL acoplados** — que **aprende a aprender** rumo a AGI-like. Verdade por número; nada fingido. **AGI-like = estrela** (ordena o build); **entrega = número pré-registrado**, non-claim até recibo. Sob `ATOMIC-INTENCAO-AUTOPOIESE-CONTINUA.md` e `ATOMIC-DOUTRINA-UNIFICADA-PESOS-APRENDIVEIS.md`. Segredos por env.

## 0. O diagnóstico honesto que pivota

O atomic **HOJE** é quase todo a metade **SIMBÓLICA-DETERMINÍSTICA** (álgebra de edição verificada (a)+(e), proof-gates, SyGuS/CVC5, library-learning, abduction, oráculo diferencial). A metade **CONEXIONISTA que APRENDE-no-loop** é o buraco: o LLM (DeepSeek) é **externo e congelado**; a **"net" — o aprendiz neural — está MORTA por número** (null cross-bug, leave-one-bug-out recall@FP0 ≈ 0, parqueada).

**Visão = neuro-simbólica. Construído = simbólico. O neural-que-aprende é a peça que falta.**

## 1. Por que a net morreu — e por que NÃO é o fim dela

A net morreu no papel **ERRADO**: **prever o conteúdo-do-fix** cross-bug — onde o movimento certo de um bug fica **vetor-idêntico** ao errado de outro (a sombra do Rice). Esse papel é **impossível por número**. **Mas o loop de síntese MUDA o trabalho da net.**

## 2. As DUAS keystones

- **Keystone SIMBÓLICA — library-learning:** comprime composições **PROVADAS** em **novos primitivos** que re-entram na gramática, **sem humano**. Cresce o **alcance**.
- **Keystone NEURAL — a net ressuscitada como modelo de reconhecimento / política:** **não prevê conteúdo — aprende a GUIAR a busca simbólica** (priorizar quais operadores compor, quais abstrações tentar, qual spec abduzir), treinada nos **PRÓPRIOS sucessos provados** do loop (proof-as-reward). É o *recognition model* da linhagem DreamCoder.

## 3. Por que Rice NÃO bloqueia o papel novo (o ponto que ressuscita a net)

Corretude é trabalho do motor **SIMBÓLICO** (a prova). A net **só aprende heurística de busca** — ela **pode errar à vontade**, porque **a prova filtra o erro de graça** (candidato rejeitado, custo ~0). Logo a net **aprende agressivamente** num espaço onde antes colidia.

**Evidência de que o papel-guia é aprendível:** o **retrieval (guiar / recuperar) FUNCIONOU — p@1 0.327, passou o controle permutado** — exatamente onde **prever-conteúdo morreu**. **O sinal aprendível mora na GUIA, não na geração.**

## 4. O loop neuro-simbólico, fechado

**neural propõe/prioriza → simbólico compõe + prova → sucesso provado (a) comprime na library (keystone simbólica) E (b) vira dado de treino da net (keystone neural) → net guia mais fundo → composições mais profundas viram alcançáveis → recursa.**

As duas keystones **se alimentam**: o simbólico dá à net **dado provado, sem ruído**; a net dá ao simbólico **busca mais profunda**. **Isto É o acoplamento neuro-simbólico — conexionista REAL + simbólico REAL, aprendendo a aprender.** Nenhuma keystone sozinha é o loop.

## 5. A prova (número, não desejo)

- **Eficiência de busca:** a net-guia melhora **solve / custo-de-busca por iteração** vs **ablação** (net-congelada / aleatória)? Held-out, permutado.
- **Alargamento recursivo:** `novel_family_resolve@k` do loop **ACOPLADO** sobe por iteração, **held-out**, **batendo a ablação**, com **F4 (recursão real)** aceso, **sem platô**.
- **Cruzou e segue subindo → o loop neuro-simbólico converge, por número.** **Platôou → teto empírico — registra honesto, diversifica (quality-diversity), continua.**

## 6. Bound honesto + guardas

**Rice fica de pé** (expressividade; sem gerador universal). Cognição é **estreita** (domínio: código), **não** consciência nem geral. **AGI-like = estrela; cognição / emergência = observada, JAMAIS declarada** (F1/F4 = números, não rótulos). Só via `expand_self` monotônico; **proof-as-reward só com verificador endurecido** (diferencial Z3×CVC5); nunca finja verde, nunca fabrique número; estudante DeepSeek V4 Pro; **quanto mais alta a estrela, mais estrita a non-claim**.

---

A net **não morreu — estava no papel errado.** No papel de **GUIA**, sob a prova que filtra seus erros de graça, ela é a **keystone neural** que faltava. **Duas keystones, um loop.** A estrela ordena; o número entrega. Provado por número, jamais por desejo.
