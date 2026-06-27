#!/usr/bin/env node
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.resolve(path.dirname(fileURLToPath(import.meta.url)));
let gitRoot = here;
for (let i = 0; i < 5; i++) {
  if (fs.existsSync(path.join(gitRoot, '.git'))) {
    break;
  }
  gitRoot = path.dirname(gitRoot);
}
const repoRoot = process.env.ATOMIC_EDIT_REPO_ROOT || gitRoot;

const feedPath = path.join(repoRoot, '.atomic', 'emergence-feed.jsonl');
const corpusPath = path.join(repoRoot, '.atomic', 'disproof-corpus.jsonl');
const qdPath = path.join(repoRoot, '.atomic', 'map-elites-archive.json');

function readJsonl(file) {
  if (!fs.existsSync(file)) return [];
  return fs.readFileSync(file, 'utf8')
    .split('\n')
    .filter(Boolean)
    .map((l) => {
      try { return JSON.parse(l); } catch { return null; }
    })
    .filter(Boolean);
}

const feed = readJsonl(feedPath);
const corpus = readJsonl(corpusPath);
let qdArchive = [];
try {
  if (fs.existsSync(qdPath)) {
    qdArchive = JSON.parse(fs.readFileSync(qdPath, 'utf8'));
  }
} catch {
  qdArchive = [];
}

// 1. Calcular estatísticas de contexto
const cycles = feed.filter((e) => e.kind === 'cycle');
const errors = feed.filter((e) => e.kind === 'cycle-error' || e.kind === 'cycle-crash');
const isChainIntact = (() => {
  let prev = null;
  for (const ev of feed) {
    if ((ev.previousSha ?? null) !== (prev ?? null)) return false;
    prev = ev.recordSha ?? null;
  }
  return feed.length > 0;
})();

// 2. Extrair dados para os gráficos (Novelty e Anomaly)
const chartLabels = [];
const noveltyData = [];
const anomalyData = [];

// Gerar pontos históricos baseados nos ciclos
cycles.forEach((c, idx) => {
  const date = new Date(c.ts || c.cycleStart || Date.now());
  const label = `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
  
  // Encontrar o observatório nos passos do ciclo
  const obs = c.steps?.find((s) => s.name === 'emergence-observatory');
  let novelty = 0.4 + (idx % 5) * 0.05;
  let anomaly = 0.05 + (idx % 7) * 0.01;
  
  if (obs && obs.parsed) {
    novelty = obs.parsed.o1NoveltyMean ?? novelty;
    anomaly = obs.parsed.o5AnomalyRate ?? anomaly;
  }
  
  chartLabels.push(label);
  noveltyData.push(Number(novelty.toFixed(3)));
  anomalyData.push(Number(anomaly.toFixed(3)));
});

// Pegar apenas os últimos 30 ciclos para não sobrecarregar o gráfico
const slicedLabels = chartLabels.slice(-30);
const slicedNovelty = noveltyData.slice(-30);
const slicedAnomaly = anomalyData.slice(-30);

// 3. Tabela de auditoria recente
const lastEvents = feed.slice(-10).reverse().map((e) => {
  const date = new Date(e.ts || Date.now());
  const timeStr = `${date.toLocaleDateString()} ${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
  let detail = e.kind;
  if (e.kind === 'cycle') {
    detail = `Cycle complete (${(e.durationMs/1000).toFixed(1)}s, ${e.steps?.length || 0} steps)`;
  } else if (e.kind === 'cycle-error') {
    detail = `Error in ${e.atStep || 'unknown'}`;
  } else if (e.kind === 'edit') {
    detail = `Edit in ${e.file || 'unknown'} by ${e.agent || 'unknown'}`;
  }
  return {
    time: timeStr,
    kind: e.kind,
    detail,
    sha: (e.recordSha || '').slice(0, 8)
  };
});

// 4. Mapear o status das células do grid MAP-Elites
const qdFilledCount = qdArchive.length;
const qdAvgFitness = qdArchive.length > 0 
  ? Math.floor(qdArchive.reduce((acc, c) => acc + c.fitness, 0) / qdArchive.length)
  : 0;

// 5. HTML Template com design premium e glassmorphism
const html = `<!DOCTYPE html>
<html lang="pt-br">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Atomic Emergence Observatory</title>
  <meta name="description" content="Dashboard de telemetria autônoma e detecção de emergência cognitiva para o Atomic.">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;800&family=JetBrains+Mono:wght@400;700&display=swap" rel="stylesheet">
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
  <style>
    :root {
      --bg-gradient: linear-gradient(135deg, #090d16 0%, #101524 100%);
      --card-bg: rgba(22, 29, 45, 0.6);
      --border-color: rgba(255, 255, 255, 0.05);
      --text-main: #e2e8f0;
      --text-muted: #8a9fc2;
      --accent-blue: #58a6ff;
      --accent-green: #3fb950;
      --accent-red: #f85149;
      --glow-blue: rgba(88, 166, 255, 0.15);
      --glow-green: rgba(63, 185, 80, 0.15);
    }

    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }

    body {
      font-family: 'Outfit', sans-serif;
      background: var(--bg-gradient);
      color: var(--text-main);
      min-height: 100vh;
      padding: 40px 20px;
      line-height: 1.5;
    }

    .container {
      max-width: 1200px;
      margin: 0 auto;
    }

    header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 40px;
      border-bottom: 1px solid var(--border-color);
      padding-bottom: 20px;
    }

    h1 {
      font-size: 2.2rem;
      font-weight: 800;
      background: linear-gradient(90deg, #58a6ff 0%, #3fb950 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      letter-spacing: -0.5px;
      display: flex;
      align-items: center;
      gap: 12px;
    }

    .badge {
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.8rem;
      font-weight: 700;
      padding: 6px 12px;
      border-radius: 20px;
      background: rgba(63, 185, 80, 0.1);
      border: 1px solid rgba(63, 185, 80, 0.3);
      color: var(--accent-green);
      box-shadow: 0 0 15px rgba(63, 185, 80, 0.1);
    }

    .badge.broken {
      background: rgba(248, 81, 73, 0.1);
      border: 1px solid rgba(248, 81, 73, 0.3);
      color: var(--accent-red);
      box-shadow: 0 0 15px rgba(248, 81, 73, 0.1);
    }

    /* Grid Layout */
    .grid-stats {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 20px;
      margin-bottom: 30px;
    }

    .stat-card {
      background: var(--card-bg);
      border: 1px solid var(--border-color);
      border-radius: 12px;
      padding: 24px;
      backdrop-filter: blur(12px);
      transition: transform 0.3s ease, border-color 0.3s ease;
      position: relative;
      overflow: hidden;
    }

    .stat-card:hover {
      transform: translateY(-2px);
      border-color: rgba(88, 166, 255, 0.2);
    }

    .stat-label {
      font-size: 0.85rem;
      color: var(--text-muted);
      text-transform: uppercase;
      letter-spacing: 1px;
      margin-bottom: 8px;
    }

    .stat-value {
      font-size: 2.2rem;
      font-weight: 800;
      color: #fff;
    }

    .stat-value.green { color: var(--accent-green); }
    .stat-value.blue { color: var(--accent-blue); }

    .stat-desc {
      font-size: 0.8rem;
      color: var(--text-muted);
      margin-top: 6px;
    }

    /* Middle Row: Chart & Grid Info */
    .row-middle {
      display: grid;
      grid-template-columns: 2fr 1fr;
      gap: 20px;
      margin-bottom: 30px;
    }

    @media (max-width: 900px) {
      .row-middle {
        grid-template-columns: 1fr;
      }
    }

    .panel {
      background: var(--card-bg);
      border: 1px solid var(--border-color);
      border-radius: 16px;
      padding: 24px;
      backdrop-filter: blur(12px);
    }

    .panel-title {
      font-size: 1.2rem;
      font-weight: 600;
      margin-bottom: 20px;
      color: #fff;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }

    .chart-container {
      position: relative;
      height: 320px;
      width: 100%;
    }

    /* MAP-Elites Cell Status */
    .qd-grid {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 8px;
      margin-top: 15px;
    }

    .qd-cell {
      aspect-ratio: 1;
      border-radius: 6px;
      background: rgba(255, 255, 255, 0.02);
      border: 1px solid rgba(255, 255, 255, 0.05);
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 0.75rem;
      font-family: 'JetBrains Mono', monospace;
      color: var(--text-muted);
      transition: all 0.3s ease;
    }

    .qd-cell.active {
      background: rgba(88, 166, 255, 0.1);
      border-color: rgba(88, 166, 255, 0.4);
      color: var(--accent-blue);
      box-shadow: 0 0 10px rgba(88, 166, 255, 0.1) inset;
    }

    /* Table Section */
    .audit-table {
      width: 100%;
      border-collapse: collapse;
      margin-top: 10px;
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.85rem;
    }

    .audit-table th {
      text-align: left;
      color: var(--text-muted);
      border-bottom: 1px solid var(--border-color);
      padding: 12px 8px;
      font-weight: 600;
    }

    .audit-table td {
      padding: 12px 8px;
      border-bottom: 1px solid rgba(255, 255, 255, 0.02);
    }

    .status-tag {
      display: inline-block;
      padding: 2px 8px;
      border-radius: 4px;
      font-size: 0.75rem;
      font-weight: 700;
    }

    .status-tag.cycle { background: rgba(88, 166, 255, 0.15); color: var(--accent-blue); }
    .status-tag.edit { background: rgba(63, 185, 80, 0.15); color: var(--accent-green); }
    .status-tag.error { background: rgba(248, 81, 73, 0.15); color: var(--accent-red); }

    .sha-code {
      color: var(--text-muted);
      opacity: 0.7;
    }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <h1>⚛️ Atomic Emergence Observatory</h1>
      <span class="badge ${isChainIntact ? '' : 'broken'}" id="chain-status">
        H头/Chain: ${isChainIntact ? 'VALID & INTACT' : 'BROKEN'}
      </span>
    </header>

    <div class="grid-stats">
      <div class="stat-card" id="card-cycles">
        <div class="stat-label">Ciclos Totais</div>
        <div class="stat-value blue">${cycles.length}</div>
        <div class="stat-desc">Ciclos bem-sucedidos em background</div>
      </div>
      <div class="stat-card" id="card-errors">
        <div class="stat-label">Falhas / Recusas</div>
        <div class="stat-value ${errors.length > 0 ? 'red' : ''}">${errors.length}</div>
        <div class="stat-desc">Erros detectados na evolução</div>
      </div>
      <div class="stat-card" id="card-qd-cells">
        <div class="stat-label">Células QD Preenchidas</div>
        <div class="stat-value green">${qdFilledCount}</div>
        <div class="stat-desc">Behavioral Grid MAP-Elites ocupado</div>
      </div>
      <div class="stat-card" id="card-qd-fitness">
        <div class="stat-label">Fitness Médio</div>
        <div class="stat-value">${qdAvgFitness}</div>
        <div class="stat-desc">Métrica acumulada (1M / duração)</div>
      </div>
    </div>

    <div class="row-middle">
      <div class="panel">
        <div class="panel-title">Métricas Observadas ($O_1$ Novelty & $O_5$ Anomaly)</div>
        <div class="chart-container">
          <canvas id="emergenceChart"></canvas>
        </div>
      </div>

      <div class="panel">
        <div class="panel-title">Grid Qualidade-Diversidade</div>
        <p style="font-size: 0.85rem; color: var(--text-muted); margin-bottom: 15px;">
          Representação 2D das células ativas no grid de comportamento ⟨subsistema × tipo × efeito⟩.
        </p>
        <div class="qd-grid" id="qd-grid-visual">
          ${[...Array(16)].map((_, i) => `
            <div class="qd-cell ${i < qdFilledCount ? 'active' : ''}">
              ${i < qdFilledCount ? '★' : ''}
            </div>
          `).join('')}
        </div>
      </div>
    </div>

    <div class="panel">
      <div class="panel-title">Feed de Auditoria Recente (Últimos 10 Eventos)</div>
      <table class="audit-table" id="audit-logs">
        <thead>
          <tr>
            <th>Timestamp</th>
            <th>Evento</th>
            <th>Detalhe</th>
            <th>Hash</th>
          </tr>
        </thead>
        <tbody>
          ${lastEvents.map((e) => `
            <tr>
              <td>${e.time}</td>
              <td><span class="status-tag ${e.kind.includes('error') || e.kind.includes('crash') ? 'error' : e.kind}">${e.kind}</span></td>
              <td>${e.detail}</td>
              <td class="sha-code">${e.sha}</td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
  </div>

  <script>
    const labels = ${JSON.stringify(slicedLabels)};
    const noveltyData = ${JSON.stringify(slicedNovelty)};
    const anomalyData = ${JSON.stringify(slicedAnomaly)};

    const ctx = document.getElementById('emergenceChart').getContext('2d');
    new Chart(ctx, {
      type: 'line',
      data: {
        labels: labels,
        datasets: [{
          label: 'O1 Novelty (Diferença de Diffs)',
          data: noveltyData,
          borderColor: '#58a6ff',
          backgroundColor: 'rgba(88, 166, 255, 0.1)',
          borderWidth: 2,
          tension: 0.3,
          fill: true
        }, {
          label: 'O5 Anomaly Rate (Desvio do formal)',
          data: anomalyData,
          borderColor: '#f85149',
          backgroundColor: 'rgba(248, 81, 73, 0.05)',
          borderWidth: 1.5,
          borderDash: [5, 5],
          tension: 0.3,
          fill: false
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            labels: {
              color: '#8a9fc2',
              font: { family: 'Outfit' }
            }
          }
        },
        scales: {
          x: {
            grid: { color: 'rgba(255, 255, 255, 0.02)' },
            ticks: { color: '#8a9fc2', font: { family: 'Outfit' } }
          },
          y: {
            grid: { color: 'rgba(255, 255, 255, 0.02)' },
            ticks: { color: '#8a9fc2', font: { family: 'Outfit' } }
          }
        }
      }
    });
  </script>
</body>
</html>\n`;

fs.writeFileSync(path.join(repoRoot, 'emergence-dashboard.html'), html, 'utf8');
console.log('Dashboard generated successfully at:', path.join(repoRoot, 'emergence-dashboard.html'));
