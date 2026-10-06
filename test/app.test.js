import test from 'node:test';
import assert from 'node:assert';
import { startServer, stopServer, app } from '../src/server.js';
import { config } from '../src/config.js';

let testPort = 3999;
let serverInstance;

test.before(async () => {
  serverInstance = await startServer(testPort);
});

test.after(async () => {
  await stopServer();
});

test('GET /health returns healthy status and uptime', async () => {
  const res = await fetch(`http://localhost:${testPort}/health`);
  assert.strictEqual(res.status, 200);
  const data = await res.json();
  assert.strictEqual(data.status, 'healthy');
  assert.strictEqual(typeof data.uptimeSeconds, 'number');
  assert.strictEqual(data.environment, config.env);
  assert.ok(data.database);
});

test('GET /api/v1/info returns application deployment metadata', async () => {
  const res = await fetch(`http://localhost:${testPort}/api/v1/info`);
  assert.strictEqual(res.status, 200);
  const data = await res.json();
  assert.strictEqual(data.appName, config.appName);
  assert.strictEqual(data.environment, config.env);
  assert.strictEqual(data.version, config.version);
  assert.strictEqual(data.commitSha, config.commitSha);
  assert.ok(data.timestamp);
});

test('POST /api/v1/tasks validates payload and creates task', async () => {
  // Invalid payload test
  const invalidRes = await fetch(`http://localhost:${testPort}/api/v1/tasks`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({}),
  });
  assert.strictEqual(invalidRes.status, 400);

  // Valid payload test
  const validRes = await fetch(`http://localhost:${testPort}/api/v1/tasks`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title: 'Smoke task test' }),
  });
  assert.strictEqual(validRes.status, 201);
  const created = await validRes.json();
  assert.strictEqual(created.data.title, 'Smoke task test');
  assert.strictEqual(created.environment, config.env);
});

test('GET /api/v1/tasks returns stored tasks', async () => {
  const res = await fetch(`http://localhost:${testPort}/api/v1/tasks`);
  assert.strictEqual(res.status, 200);
  const data = await res.json();
  assert.strictEqual(data.environment, config.env);
  assert.ok(Array.isArray(data.data));
  assert.ok(data.count >= 1);
});

test('GET /unknown-route returns 404', async () => {
  const res = await fetch(`http://localhost:${testPort}/non-existent`);
  assert.strictEqual(res.status, 404);
  const data = await res.json();
  assert.strictEqual(data.error, 'Route not found');
});
