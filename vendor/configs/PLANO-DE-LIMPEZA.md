# Plano de Limpeza Profunda do Repositorio Kloel

Status: FASE 1 concluida como inventario/plano. Nenhum arquivo foi movido ou deletado do repo nesta fase.

## Baseline

- Repo: `/Users/danielpenin/kloel`
- Branch atual: `feat/kloelgraph-prototype-engine`
- HEAD local inventariado: `9dff793d25ccb20470cac3239647509339e0bd85`
- Remote principal: `origin https://github.com/danielgonzagat/Kloel.git`
- Package manager detectado: `npm` (`package-lock.json` na raiz, backend, frontend, worker e e2e)
- Working tree: suja e confirmada por Daniel como base aprovada para a limpeza.

## Caminhos externos da execucao

- Manifestos da Fase 1: `/Users/danielpenin/_KLOEL_LIMPEZA_2026-06-03-0940/MANIFESTS`
- Backup futuro da Fase 2: `/Users/danielpenin/_KLOEL_LIMPEZA_2026-06-03-0940/BACKUP`
- Lixeira local futura da Fase 2: `/Users/danielpenin/_KLOEL_LIMPEZA_2026-06-03-0940/LIXO`
- Arquivo permanente fora do GitHub para ferramentas/build/P&D: `/Users/danielpenin/KLOEL_FERRAMENTAS_BUILD`

## Manifestos gerados

- `repo-files-before.txt`: 477930 arquivos locais fora de `.git` e `node_modules`.
- `git-tracked-before.txt`: 6678 arquivos rastreados.
- `untracked-before.txt`: 92 arquivos nao rastreados.
- `suspicious-paths.txt`: 11135 caminhos locais suspeitos por nome.
- `suspicious-content-rg.txt`: 245896 linhas com termos suspeitos.
- `large-files.txt`: 728 arquivos locais maiores que 1 MB.
- `entrypoint-configs-clean.txt`: configs e entrypoints de produto/deploy/teste.
- `package-scripts.txt`: scripts/deps dos `package.json`.
- `pulse-references.txt`: referencias Pulse.
- `agents-mcp-references.txt`: referencias MCP/agentes/tooling.
- `category-a-keep-anchors.txt`: 5452 ancoras de produto/config.
- `category-b-archive-candidates.txt`: 462 candidatos rastreados para arquivar fora do repo.
- `category-c-delete-candidates.txt`: 6 candidatos rastreados para lixeira local.
- `category-d-review-candidates.txt`: 512 candidatos brutos ambiguos/produto-adjacentes.

## Criterio usado

O corte primario foi alcancabilidade por produto/build/deploy/teste:

- A: manter no repo quando for runtime, build, deploy, teste, Prisma, asset, config real ou doc operacional minima.
- B: arquivar fora do repo quando for Pulse, MCP, agente, Codex/OpenCode/Kilo/Hermes/Claude tooling, graph/tooling de construcao ou doc historica util.
- C: enviar para lixeira local quando for log, backup/relatorio temporario, cache ou legado inequivoco.
- D: nao agir quando a superficie puder ser produto atual/futuro, teste real ou operacional ambigua.

## Categoria A - MANTER NO REPO

Superficies que passam no teste de essencialidade:

- `package.json`, `package-lock.json`, lockfiles e configs de Node/NPM.
- `.env.example`, `.gitignore`, `.dockerignore`, `.editorconfig`, configs de build/lint/teste necessarias.
- `backend/package.json`, `backend/package-lock.json`, `backend/Dockerfile`, `backend/railway.toml`, `backend/nest-cli.json`, `backend/tsconfig*.json`.
- `backend/prisma/**`, incluindo `schema.prisma`, migrations reais e scripts Prisma.
- `backend/src/**` de produto, exceto superficies Pulse listadas em B.
- `frontend/package.json`, `frontend/package-lock.json`, `frontend/Dockerfile`, `frontend/next.config.ts`, `frontend/tsconfig.json`, `frontend/src/**`, `frontend/public/**`.
- `worker/package.json`, `worker/package-lock.json`, `worker/Dockerfile`, `worker/railway.*`, `worker/prisma/**`, `worker/*.ts`, `worker/src/**` quando existir.
- `e2e/**` enquanto for suite real de validacao.
- `.github/workflows/ci-cd.yml`, `deploy-production.yml`, `deploy-staging.yml`, `codeql.yml`, `codacy-analysis.yml`, `dependabot-auto-merge.yml`, `release-please.yml`, `visual-regression.yml`, `canonicalization-gates.yml`, depois de limpas referencias Pulse/agentes.
- `README.md`, `RUNBOOK.md`, `SECURITY.md`, `TESTING.md`, `ARCHITECTURE.md`, depois de reduzidos a documentacao operacional minima atual.
- `docs/api/**`, `docs/compliance/**`, `docs/runbooks/**`, `docs/security/**`.
- Kloel AI/product internals como `backend/src/kloel/agent-runtime/**`, `backend/src/kloel/mind/**`, `backend/src/kloel/cia/**` e `backend/src/kloel/unified-agent*`: manter por enquanto, pois sao importados por `KloelModule`/`AppModule` e podem ser produto Kloel, nao tooling externo.

Manifesto completo: `/Users/danielpenin/_KLOEL_LIMPEZA_2026-06-03-0940/MANIFESTS/category-a-keep-anchors.txt`.

## Categoria B - ARQUIVAR FORA DO REPO

Destino: `/Users/danielpenin/KLOEL_FERRAMENTAS_BUILD`, preservando estrutura de caminho.

Candidatos claros:

- `.mcp.json`.
- `scripts/mcp/**` (290 arquivos rastreados), incluindo `atomic-edit`, `lsp-mesh`, `cognitive-hub`, `codacy`, `railway`, `stripe`, `sentry`, `graphify-plus`, `task-graph`, `test-runner`, `postgres`, etc.
- `scripts/pulse/**` e qualquer estado em `scripts/.pulse/**`.
- `backend/src/pulse/**` e `backend/test/pulse/**`.
- `backend/src/kloel/pulse-gates/**`.
- `AGENTS.md`, `CLAUDE.md`, `CODEX.md`.
- `.kilo/**`, `.opencode/**`, `.serena/**`, `.beads/**`, `.codegraph/**`, `.gitnexus/**` quando rastreados.
- `tools/agent-coordination/**`, `tools/auto-pr/**`, `tools/graphify-plus/**`, `tools/codegraph-live/**`, `tools/cognitive-hub/**`, `tools/dap-bridge/**`, `tools/hud-portable/**`, `tools/loop-runner/**`, `tools/lsp-mesh/**`, `tools/memory-curator/**`, `tools/saas-compiler/**`, `tools/session-state/**`, `tools/test-affected/**`, `tools/visual-fidelity/**`.
- Docs historicas/tooling: `docs/atomic/**`, `docs/superpowers/**`, `docs/devtools/gitnexus-mcp.md`, `docs/HUD_README.md`, `docs/KLOEL-HANDOFF.md`, `docs/implementation/kloel-cia-*`, `docs/contracts/pci/04-pulse-gates.md`, `docs/architecture/MCP_*`, `docs/architecture/OMNICORE_*`, `docs/architecture/CANONICALIZATION_MISSION.md`, `docs/architecture/GRAPHIFY_DUPLICATES.md`.
- Root `PULSE_*.json` nao rastreados e `scripts/.pulse/**`: arquivar fora do repo, nao comitar.

Referencias funcionais que precisam ser limpas na Fase 2:

- `backend/src/app.module.ts`: remove `PulseModule` e `PulseGatesModule` dos imports e do array `imports`.
- `backend/src/kloel/kloel.module.ts`: remove dependencia de `PulseArtifactService`.
- `backend/src/kloel/abi/**`, `backend/src/kloel/self-awareness/**`, `backend/src/kloel/v-tier/**`: substituir nomes/contratos Pulse por contratos de produto ou remover feature se for so gate Pulse.
- `package.json`: remover scripts `agent:*`, `graph:*`, `gitnexus:*`, `memory:*`, `auto-pr:*`, scripts de `ratchet:*` e scripts que apontam para MCP/agent tooling; limpar `quality:static` para nao depender de `ratchet:check`.
- `package.json`: revisar/remover deps root usadas so por tooling: `@opencode-ai/sdk`, `@openai/agents`, `@modelcontextprotocol/sdk` e possivelmente `ts-morph` se ficar usado so por codemods/tooling.
- `.github/workflows/claude.yml` e `.github/workflows/claude-code-review.yml`: remover do repo.
- `.github/workflows/nightly-ops-audit.yml`: remover ou reduzir a uma rotina operacional sem Pulse/ratchet.
- `.github/workflows/ci-cd.yml`: remover upload/nomes `PULSE` e `ratchet`.
- `README.md`, `RUNBOOK.md`, `SECURITY.md`, `TESTING.md`, `ARCHITECTURE.md`: remover secoes PULSE/MCP/agentes e reescrever como docs Kloel minimas.

Manifesto completo: `/Users/danielpenin/_KLOEL_LIMPEZA_2026-06-03-0940/MANIFESTS/category-b-archive-candidates.txt`.

## Categoria C - DELETAR DO REPO COMO MORTO

Destino de seguranca: `/Users/danielpenin/_KLOEL_LIMPEZA_2026-06-03-0940/LIXO`, preservando estrutura. Nao apagar fisicamente ainda.

- `.backup-manifest.json`
- `.backup-validation.log`
- `.dr-test.log`
- `CHANGELOG.md` (historico contaminado por tooling/agentes e nao necessario para build/deploy)
- `docs/production-hardening/docs-production-hardening-temp-20260427/HANDOFF.md`
- `docs/production-hardening/docs-production-hardening-temp-20260427/PRODUCTION_HARDENING_REPORT.md`

Manifesto completo: `/Users/danielpenin/_KLOEL_LIMPEZA_2026-06-03-0940/MANIFESTS/category-c-delete-candidates.txt`.

## Categoria D - DECIDIR / NAO AGIR SEM DECISAO

Itens ambiguos. A Fase 2 nao deve remover estes sem decisao objetiva:

- `frontend-admin/**`: nao aparece no `npm run build` raiz, mas pode ser admin/produto separado. Pergunta: manter como produto ou arquivar como legado?
- `tools/e2e-sandbox/**`: nao e produto, mas pode ser suporte real de teste. Pergunta: manter como teste operacional ou arquivar?
- `tools/db-sample/**`, `tools/fingerprint/**`, `tools/metrics/**`, `tools/production-twin/**`, `tools/stripe/**`: utilitarios possivelmente operacionais. Pergunta: manter so se forem usados por runbook/deploy/teste real.
- `docs/audits/**`, `docs/plans/**`, `docs/architecture/*AUDIT*`, `docs/production-hardening/**`, `docs/evidence/**`, `docs/intel/**`: docs historicas. Pergunta: arquivar tudo fora do repo e manter apenas docs operacionais minimas?
- `scripts/ops/**`: governance/prod-readiness. Pergunta: manter apenas scripts chamados por CI/pre-push/deploy e remover todo o resto?
- `ops/**`: governance protegida. Pergunta: manter apenas boundary atual e remover airlocks/ratchets legados?
- `codecov.yml`, `.codacy.yml`, `docs/codacy/**`: manter se Codacy/Codecov continuarem como qualidade oficial; arquivar se a limpeza remover governanca externa.

Manifesto bruto: `/Users/danielpenin/_KLOEL_LIMPEZA_2026-06-03-0940/MANIFESTS/category-d-review-candidates.txt`.

## Prova de uso relevante encontrada

- `backend/src/app.module.ts` importa `PulseModule` e `PulseGatesModule`. Portanto remover Pulse exige refatoracao/desacoplamento, nao apenas remocao de arquivos.
- `backend/src/kloel/kloel.module.ts` importa `PulseArtifactService`. Portanto parte de KloelModule ainda depende de `backend/src/pulse`.
- `backend/src/kloel/v-tier/v-tier-certifier.service.ts` importa gates Pulse. Se `v-tier` ficar, precisa contrato novo sem Pulse.
- `backend/src/kloel/abi/abi.module.ts` usa `PulseTruthSnapshotService`. Precisa renomear/remover para snapshot de produto ou cortar.
- `root package.json` ainda expoe scripts de agent/MCP/graph/GitNexus/ratchet.
- Workflows ainda contem Claude Actions, ratchet e uploads PULSE.
- `.gitignore` ja ignora muitos artefatos de agentes e caches; a Fase 2 deve reforcar `PULSE_*.json`, `scripts/.pulse/`, `.atomic/_*.mjs` e outros scratch files se necessario.

## Plano da Fase 2, se aprovado

1. Criar backup completo:
   - `tar -czf /Users/danielpenin/_KLOEL_LIMPEZA_2026-06-03-0940/BACKUP/repo-fulltree.tar.gz ...`
   - `git bundle create /Users/danielpenin/_KLOEL_LIMPEZA_2026-06-03-0940/BACKUP/repo-historico.bundle --all`
2. Criar branch `chore/limpeza-profunda-2026-06-03-0940`.
3. Mover categoria B para `/Users/danielpenin/KLOEL_FERRAMENTAS_BUILD`.
4. Mover categoria C para `/Users/danielpenin/_KLOEL_LIMPEZA_2026-06-03-0940/LIXO`.
5. Limpar referencias orfas em `package.json`, workflows, docs minimas e modulos backend.
6. Resolver o desacoplamento Pulse no backend antes de validar.
7. Atualizar lockfiles se deps root forem removidas.
8. Rodar validacao maxima:
   - `npm run prisma:validate`
   - `npm run prisma:generate`
   - `npm run typecheck`
   - `npm run lint`
   - `npm run test`
   - `npm run build`
   - checks especificos de backend/frontend/worker se necessarios
9. Gerar manifestos finais e `docs/REPO_CLEANUP_REPORT.md`.
10. Commit local:
   - `git add -A`
   - `git commit -m "chore: deep clean repository around Kloel essentials"`
11. Nao fazer push sem autorizacao explicita.

## Riscos

- Remover Pulse quebra o backend hoje se os imports nao forem limpos.
- Remover MCP/agent tooling exige limpar `package.json`, `.mcp.json`, docs e workflows juntos para evitar referencias quebradas.
- `frontend-admin/**` pode ser produto admin separado; precisa decisao antes de remover.
- Remover ratchet/governance pode afetar CI atual; deve ser substituido por gates essenciais nao Pulse ou removido dos workflows simultaneamente.
- Os arquivos protegidos atuais precisarao ser alterados na Fase 2; isso exige a aprovacao explicita contida em `APROVADO`.

AGUARDANDO APROVACAO - nada foi movido, deletado, commitado ou enviado para o GitHub.
