import { spawn } from 'child_process';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import assert from 'assert';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const serverPath = path.join(__dirname, 'server.mjs');
const repoRoot = path.resolve(__dirname, '../../..');

// Clean up any existing DB/ledger first to have a clean slate
const ledgerFile = path.join(repoRoot, '.atomic', 'semantic-memory-ledger.jsonl');
const dbFile = path.join(repoRoot, '.atomic', 'semantic-memory.db');

try { fs.unlinkSync(ledgerFile); } catch {}
try { fs.unlinkSync(dbFile); } catch {}

const proc = spawn('node', ['--experimental-sqlite', serverPath], {
  cwd: repoRoot,
  env: {
    ...process.env,
    ATOMIC_SWARM_REPO_ROOT: repoRoot
  }
});

let buffer = '';
let messageId = 1;
const pendingRequests = new Map();

proc.stdout.on('data', (data) => {
  buffer += data.toString();
  let newlineIndex;
  while ((newlineIndex = buffer.indexOf('\n')) !== -1) {
    const line = buffer.slice(0, newlineIndex).trim();
    buffer = buffer.slice(newlineIndex + 1);
    if (line) {
      try {
        const response = JSON.parse(line);
        if (response.id && pendingRequests.has(response.id)) {
          const { resolve, reject } = pendingRequests.get(response.id);
          pendingRequests.delete(response.id);
          resolve(response);
        }
      } catch (e) {
        console.error('Failed to parse response line:', line, e);
      }
    }
  }
});

proc.stderr.on('data', (data) => {
  console.log('SERVER LOG/STDERR:', data.toString().trim());
});

function sendRequest(method, params) {
  return new Promise((resolve, reject) => {
    const id = messageId++;
    pendingRequests.set(id, { resolve, reject });
    const payload = { jsonrpc: '2.0', id, method, params };
    proc.stdin.write(JSON.stringify(payload) + '\n');
  });
}

async function runTests() {
  // Wait for server to boot
  await new Promise(r => setTimeout(r, 1000));

  console.log('Sending memory_record...');
  const rec1 = await sendRequest('tools/call', {
    name: 'memory_record',
    arguments: {
      intent: 'Refactored user authentication module to support OAuth2 login.',
      relatedFiles: ['src/auth.ts', 'src/oauth.ts'],
      relatedTaskIds: [1024, 'task-42'],
      tags: ['auth', 'oauth', 'security'],
      symbols: ['authenticateUser', 'OAuth2Provider'],
      lockIds: ['lock-auth-123'],
      gitCommit: 'abc1234567890ef'
    }
  });

  console.log('Record Response:', JSON.stringify(rec1, null, 2));
  assert(rec1.result, 'record failed');
  const resObj = JSON.parse(rec1.result.content[0].text);
  assert(resObj.ok === true, 'ok is not true');
  assert(resObj.hash, 'hash missing');

  // Test queries
  console.log('Querying by query keyword...');
  const q1 = await sendRequest('tools/call', {
    name: 'memory_query',
    arguments: { query: 'oauth2' }
  });
  const resQ1 = JSON.parse(q1.result.content[0].text).results;
  assert(resQ1.length === 1, 'query oauth2 failed');

  console.log('Querying by file...');
  const q2 = await sendRequest('tools/call', {
    name: 'memory_query',
    arguments: { file: 'src/oauth.ts' }
  });
  const resQ2 = JSON.parse(q2.result.content[0].text).results;
  assert(resQ2.length === 1, 'query file failed');
  assert(resQ2[0].files.includes('src/oauth.ts'), 'file not returned');
  assert(resQ2[0].tasks.includes('1024'), 'task not returned');
  assert(resQ2[0].locks.includes('lock-auth-123'), 'lock not returned');

  console.log('Querying by symbol...');
  const q3 = await sendRequest('tools/call', {
    name: 'memory_query',
    arguments: { symbol: 'authenticateUser' }
  });
  const resQ3 = JSON.parse(q3.result.content[0].text).results;
  assert(resQ3.length === 1, 'query symbol failed');
  assert(resQ3[0].symbols.includes('authenticateUser'), 'symbol not returned');

  console.log('Querying by taskId...');
  const q4 = await sendRequest('tools/call', {
    name: 'memory_query',
    arguments: { taskId: 1024 }
  });
  const resQ4 = JSON.parse(q4.result.content[0].text).results;
  assert(resQ4.length === 1, 'query taskId failed');

  console.log('Querying with unmatched tag...');
  const q5 = await sendRequest('tools/call', {
    name: 'memory_query',
    arguments: { tag: 'unknown-tag' }
  });
  const resQ5 = JSON.parse(q5.result.content[0].text).results;
  assert(resQ5.length === 0, 'query unknown-tag should be empty');

  console.log('All tests PASSED!');
  proc.kill();
  process.exit(0);
}

runTests().catch(err => {
  console.error('Test failed:', err);
  proc.kill();
  process.exit(1);
});
