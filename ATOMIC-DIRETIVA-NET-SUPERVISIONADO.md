# SUPERSEDIDO/PARKED — Prova 1 NULL para fix-content cross-bug

A **Prova 1 held-out** (leave-one-bug-out, rótulos oficiais) deu **recall@FP0 ≈ 0** (lex 0.000, du 0.009, fundido 0.000). O ~0.85 era **in-sample (decora)**; **controle permutado idêntico**; **curva plana**. O net supervisionado **não generaliza** o fix-content cross-bug com o corpus atual. Isso deixa o fix-content-net **PARKED**, não morto, e não refuta o princípio de aprendizado.

**Razão mecânica:** cross-bug, o movimento certo de um bug fica **vetor-idêntico** ao errado de outro (o COMO é bug-específico; features name-agnostic colidem) — nenhum classificador separa vetores idênticos. Informação ausente das features, não falta de capacidade. Isto unifica todos os nulos (0 fix-shape, G2 WHERE-not-HOW, trava lexical).

**Portão para reabrir:** só com **≥50–100 tasks oficiais do SWE-Bench Pro**, held-out leave-one-bug-out, controle permutado plano, sem replay nem vazamento de problem-statement. **>0.25 revive; ≤0.20 mata de vez.**

**Direção atual → `ATOMIC-DIRETIVA-ELEVACAO-POR-PROCESSO.md`:** não gaste rounds no fix-content-net enquanto ele está PARKED; amplifique **processo + eliminação within-task + navegação + piso de correção**; meça **Elevação por número** só como coluna-frontier pareada em SWE-Bench Pro oficial.

Provado por número, jamais por desejo.
