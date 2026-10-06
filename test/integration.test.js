import test from 'node:test';
import assert from 'node:assert';
import { startServer, stopServer } from '../src/server.js';
import { config } from '../src/config.js';

let integrationPort = 3998;

test.before(async () => {
  await startServer(integrationPort);
});

test.after(async () => {
  await stopServer();
});

test('Integration: Concurrency stress check on task creation', async () => {
  const titles = ['Batch 1', 'Batch 2', 'Batch 3', 'Batch 4', 'Batch 5'];
  const promises = titles.map((title) =>
    fetch(`http://localhost:${integrationPort}/api/v1/tasks`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title: `${title} - ${config.env}` }),
    }).then((r) => r.json())
  );

  const results = await Promise.all(promises);
  assert.strictEqual(results.length, 5);
  for (const item of results) {
    assert.ok(item.data.id);
    assert.strictEqual(item.environment, config.env);
  }
});

test('Integration: Health probe stability check', async () => {
  for (let i = 0; i < 3; i++) {
    const res = await fetch(`http://localhost:${integrationPort}/health`);
    assert.strictEqual(res.status, 200);
    const body = await res.json();
    assert.strictEqual(body.status, 'healthy');
  }
});
