#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { inheritedAtomicHostEnv } from './proof-host-env.mjs';

const jsonMode = process.argv.includes('--json');
const sourceDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(sourceDir, '..', '..');
const read = (rel) => fs.readFileSync(path.join(repoRoot, rel), 'utf8');
const broker = read('core/atomic-edit/atomic-exec-broker.mjs');
const execTools = read('core/atomic-edit/server-tools-exec.ts');
const selfTools = read('core/atomic-edit/server-tools-self.ts');
const proofEnv = read('core/atomic-edit/gates/proof-host-env.mjs');
const launcherImpl = read('core/atomic-edit-mcp-launcher-impl.sh');
const supervisor = read('core/atomic-edit/launcher-supervisor.mjs');
const results = [];
function record(name, ok, detail = {}) { results.push({ name, ok: Boolean(ok), detail }); }

function withEnv(env, run) {
  const saved = { ...process.env };
  try {
    for (const key of Object.keys(process.env)) {
      if (key.startsWith('ATOMIC_') || key === 'CODEX_PROJECT_DIR' || key === 'TMPDIR' || key === 'TMP' || key === 'TEMP') delete process.env[key];
    }
    Object.assign(process.env, env);
    return run();
  } finally {
    for (const key of Object.keys(process.env)) {
      if (!(key in saved)) delete process.env[key];
    }
    for (const [key, value] of Object.entries(saved)) process.env[key] = value;
  }
}

function writeBrokerMarker(dir, marker) {
  fs.mkdirSync(path.join(dir, 'requests'), { recursive: true });
  fs.mkdirSync(path.join(dir, 'responses'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'broker.json'), JSON.stringify(marker, null, 2) + '\n');
}

function behavioralProof() {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'atomic-proof-host-env-'));
  const proofRepo = path.join(work, 'repo');
  const staleDir = path.join(proofRepo, '.atomic', 'stale-broker');
  const liveDir = path.join(proofRepo, '.atomic', 'live-broker');
  const staleEndpoint = pathToFileURL(staleDir).href;
  const liveEndpoint = pathToFileURL(liveDir).href;
  try {
    writeBrokerMarker(staleDir, { protocol: 'atomic-file-broker-v1', pid: 99999999, root: proofRepo, allowedRoot: proofRepo });
    writeBrokerMarker(liveDir, { protocol: 'atomic-file-broker-v1', pid: process.pid, root: proofRepo, allowedRoot: proofRepo });
    const staleExplicit = withEnv({ ATOMIC_EXEC_BROKER_SOCKET: staleEndpoint, ATOMIC_HOST_SANDBOX: 'macos-sandbox-exec', ATOMIC_HOST_ATOMIC_ONLY: '1' }, () => inheritedAtomicHostEnv(proofRepo));
    const liveExplicit = withEnv({ ATOMIC_EXEC_BROKER_SOCKET: liveEndpoint, ATOMIC_HOST_SANDBOX: 'macos-sandbox-exec', ATOMIC_HOST_ATOMIC_ONLY: '1' }, () => inheritedAtomicHostEnv(proofRepo));
    fs.mkdirSync(path.join(proofRepo, '.atomic'), { recursive: true });
    fs.writeFileSync(path.join(proofRepo, '.atomic', 'codex-broker-current.json'), JSON.stringify({ agent: 'codex', repoRoot: proofRepo, socket: staleEndpoint }, null, 2) + '\n');
    const staleState = withEnv({ ATOMIC_USE_BROKER_STATE: '1' }, () => inheritedAtomicHostEnv(proofRepo));
    fs.writeFileSync(path.join(proofRepo, '.atomic', 'codex-broker-current.json'), JSON.stringify({ agent: 'codex', repoRoot: proofRepo, socket: liveEndpoint }, null, 2) + '\n');
    const liveState = withEnv({ ATOMIC_USE_BROKER_STATE: '1' }, () => inheritedAtomicHostEnv(proofRepo));
    return {
      staleExplicitRejected: staleExplicit.ATOMIC_EXEC_BROKER_SOCKET === '',
      liveExplicitAccepted: liveExplicit.ATOMIC_EXEC_BROKER_SOCKET === liveEndpoint,
      staleStateRejected: staleState.ATOMIC_EXEC_BROKER_SOCKET === '',
      liveStateAccepted: liveState.ATOMIC_EXEC_BROKER_SOCKET === liveEndpoint,
      staleExplicitSocket: staleExplicit.ATOMIC_EXEC_BROKER_SOCKET,
      liveExplicitSocket: liveExplicit.ATOMIC_EXEC_BROKER_SOCKET,
      staleStateSocket: staleState.ATOMIC_EXEC_BROKER_SOCKET,
      liveStateSocket: liveState.ATOMIC_EXEC_BROKER_SOCKET,
    };
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
}

record('file broker publishes broker.json liveness marker before readiness', broker.includes("writeJsonAtomic(path.join(root, 'broker.json')") && broker.includes("protocol: 'atomic-file-broker-v1'") && broker.includes('pid: process.pid') && broker.indexOf("path.join(root, 'broker.json')") < broker.indexOf("ATOMIC_BROKER_READY file://"), { hasBrokerJson: broker.includes("path.join(root, 'broker.json')"), hasProtocol: broker.includes("atomic-file-broker-v1") });
record('atomic_exec accepts file broker endpoints only with live marker', execTools.includes("path.join(dir, 'broker.json')") && execTools.includes("marker.protocol !== 'atomic-file-broker-v1'") && execTools.includes('process.kill(marker.pid, 0)') && execTools.includes("path.join(dir, 'requests')") && execTools.includes("path.join(dir, 'responses')"), { hasMarker: execTools.includes("path.join(dir, 'broker.json')") });
record('self-expansion accepts file broker endpoints only with live marker', selfTools.includes("path.join(dir, 'broker.json')") && selfTools.includes("marker.protocol !== 'atomic-file-broker-v1'") && selfTools.includes('process.kill(marker.pid, 0)'), { hasMarker: selfTools.includes("path.join(dir, 'broker.json')") });
record('host proof env filters explicit and state brokers through marker-aware compatibility', proofEnv.includes('function compatibleBrokerEndpoint(endpoint, requiredRoot)') && proofEnv.includes('const info = brokerEndpointInfo(endpoint)') && proofEnv.includes('const explicitSocket = compatibleBrokerEndpoint(explicitCandidate, requiredRoot) ? explicitCandidate :') && proofEnv.includes('const stateSocket = useSharedBrokerState && !suppressInheritedBroker && compatibleBrokerEndpoint(state?.socket, requiredRoot) ? state.socket :') && proofEnv.includes("path.join(dir, 'broker.json')") && proofEnv.includes("marker?.protocol !== 'atomic-file-broker-v1'"), { explicitFiltered: proofEnv.includes('const explicitSocket = compatibleBrokerEndpoint(explicitCandidate, requiredRoot) ? explicitCandidate :'), stateFiltered: proofEnv.includes('compatibleBrokerEndpoint(state?.socket, requiredRoot)') });
record('launcher rejects stale file broker directories in recovery and host preflight', launcherImpl.includes('function fileBrokerMarkerAlive(dir)') && launcherImpl.includes('!fileBrokerMarkerAlive(dir)') && launcherImpl.includes('file broker liveness marker is stale or invalid') && launcherImpl.includes('self-hosted file broker did not publish liveness marker'), { hasRecoveryMarker: launcherImpl.includes('function fileBrokerMarkerAlive(dir)'), hasPreflightMarker: launcherImpl.includes('file broker liveness marker is stale or invalid') });
record('supervisor treats file broker alive only when marker protocol and pid are live', supervisor.includes("path.join(dir, 'broker.json')") && supervisor.includes("marker?.protocol !== 'atomic-file-broker-v1'") && supervisor.includes('process.kill(marker.pid, 0)') && supervisor.includes('missingBrokerSocket80'), { hasMissingSocketGuard: supervisor.includes('missingBrokerSocket80') });
const behavior = behavioralProof();
record('host proof env behavior rejects stale marker brokers and accepts live marker brokers', behavior.staleExplicitRejected && behavior.liveExplicitAccepted && behavior.staleStateRejected && behavior.liveStateAccepted, behavior);

const ok = results.every((entry) => entry.ok);
if (jsonMode || !ok) console.log(JSON.stringify({ ok, results }, null, 2));
process.exit(ok ? 0 : 1);
