# ATOMIC — Diretiva: A ESCADA DE TEORIAS (de inventar operador → adquirir teoria), no ENGINE VIVO

> O próximo nível inédito. Meta-síntese provou inventar operador DENTRO de uma teoria (0→2/3) e bateu o muro da TEORIA (popcount/Extract fora dela = 0). O salto: **subir a uma teoria mais rica.** Ambição máxima, disciplina máxima — é a disciplina que torna a ambição real. Verdade por número; emergência observada-JAMAIS-declarada. Segredos env — **rotacione as do chat.**

---

## §0. Realidade fiel (a base honesta, incl. a divergência)

- Engine: HEAD `5a76154`, **30 uncommitted, nada commitado.**
- **Ganhos recentes (meta-síntese 0→2/3, M4b autonomia sound, reparo do corpus) são REAIS na sessão, mas vivem em scratchpad+memória — não no estado durável.** O corpus no root do repo mostra **109 recs / schema antigo / sem backup**, que **NÃO bate** com o "137 reparado" (provável: reparo no engine-root ≠ repo-root; ambiguidade de root/cache).
- 2º bloqueador: `server-tools-self.ts:1169` = admissão-de-self-expansion em volta da escrita do corpus.
- **Regra-zero:** **PERSISTIR antes de ESCALAR.** Nenhum experimento novo conta se rodar só no scratchpad-brinquedo (lá tudo re-deriva). Confirmar o corpus canônico do engine vivo + persistir os ganhos + reconectar é pré-condição.

## §1. A virada inédita — ESCADA DE TEORIAS (o que ninguém fez aqui)

A progressão da autonomia, por número:
**SELEÇÃO** (M4b: pega ilha do catálogo) → **INVENÇÃO** (meta-síntese: cria operador dentro de uma teoria) → **AQUISIÇÃO DE TEORIA** (novo): quando a teoria atual não basta (oráculo sound diz "fora de toda ilha E de toda invenção desta teoria"), o sistema **adquire uma teoria mais rica** (bitvector-extract, strings, sequences, datatypes, arrays…), proof-carrying, e segue subindo.

Cada degrau **empurra o Rice um nível acima**; a **torre de teorias** é o alcance. Não é magia: é uma **hierarquia finita e bem-definida** (as teorias SMT), subida soundly.

**Portão (pré-registrado, held-out):** uma família que morria na borda de uma teoria (ex. popcount, precisa de Extract) passa a resolver **depois** do sistema **auto-adquirir a teoria certa**, proof-carrying — e uma família fora de **TODA** teoria disponível fica **0** (Rice no topo da torre, não apagado). Controle: sem aquisição = 0.

## §2. Os mecanismos de apoio (cada um grounded no que comprovadamente funciona)

- **ATLAS SOUND do inalcançável.** Cada "no-solution" sound é uma coordenada do boundary. Acumule num **atlas** (sound, per-instância — o jeito CERTO que o M4-neural falhou em fazer por predição). O atlas diz **QUAL teoria** cada região inalcançável precisa → **dirige a aquisição (§1) sem predição neural.** (Substitui a fronteira-neural-nula por acumulação sound.)
- **TRANSFERÊNCIA DE ESTRUTURA cross-teoria.** Ao resolver uma família na teoria X, mapeie a **FORMA** da solução (estrutura/WHERE — que transfere; **não** conteúdo — que morre) para teorias análogas (replace↔substitute, shift↔multiply…). Reusa **estrutura provada** entre domínios.
- **DISPROOF-CORPUS como PRIOR GERADOR.** Os disprovas acumulados **esculpem** o espaço de solução (removem o que é errado) — um **prior de PODA** para a síntese, **não** uma feature de ranking (o M2 mostrou que como feature ela perde pro content). Amplifica o único sinal que já elevou (disprova), na escala do corpus.
- **CURRÍCULO DE DUREZA AUTO-GERADO.** O sistema gera famílias progressivamente mais duras (que exigem teorias mais ricas), **forçando a si mesmo a subir a escada.** Recompensa = expandir o que alcança soundly. Open-ended, movido pelo **oráculo sound** (não pelos componentes neurais nulos).

## §3. Tudo no ENGINE VIVO, com ganhos PERSISTIDOS

A escada só significa algo no engine real (código real, teorias reais). Ordem:
1. **Confirmar o corpus canônico** que o engine vivo lê; **persistir o reparo + meta-síntese + M4b lá** (não no scratchpad); reconectar o MCP engine-rooted.
2. **Testar `expand_self` admite** (smoke proof). Se sim → fork aberto. Se ainda travar em `server-tools-self.ts:1169` → fix-de-fonte + restart (decisão do operador) — mas a metade do corpus fica permanentemente persistida.
3. **Só então** landar escada+atlas+transferência+prior no engine vivo, sobre famílias reais.

## §4. Emergência por SURPRESA (a vigília honesta, onde ela pode existir)

No engine vivo, emergência = **surpresa MEDIDA** no stream de invenção/aquisição: o sistema adquirindo teorias numa **ordem/combinação que nenhum humano desenhou**; **reuso recursivo** de uma invenção num contexto não-antecipado (F4); uma família resolvida por uma **escada de teorias auto-construída**. **Observada, JAMAIS declarada.** F1/F4 ligados no stream real. (O brinquedo é pequeno demais pra isso por construção — por isso, engine vivo.)

## §5. Guardas (a disciplina que torna a ousadia REAL)

Ambição máxima — e por isso: **persistir antes de escalar** (nada de scratchpad contar como entrega); barra brutal (held-out + permutado + ablação + multi-seed + CI + re-score); **Rice de pé** (agora no topo da torre); **search-cliff é real** — cada degrau usa uma teoria tratável, senão engasga (meça, não tune); emergência observada-jamais-declarada; só via `expand_self` proof-carrying; segredos env + rotacionados; estudante DeepSeek V4 Pro; non-claim até recibo. **Coragem aqui não é fingir verde — é rodar no real e aceitar o número.** Quanto mais alta a estrela, mais estrita a non-claim.

---

**O salto, em uma frase:** a autonomia já subiu de SELECIONAR ilha → INVENTAR operador (meta-síntese ✓); o próximo nível inédito é **ADQUIRIR TEORIA** — uma escada onde o sistema mapeia soundly seu próprio inalcançável (atlas), reconhece qual teoria mais rica cada muro exige, a adquire proof-carrying e transfere estrutura provada entre teorias, movido por disprova e por um currículo de dureza que ele mesmo gera — **tudo no engine vivo, com os ganhos persistidos, e a emergência medida como surpresa real, jamais declarada.** Ousar onde ninguém ousou = subir a escada de teorias no real; provado por número, jamais por desejo.
