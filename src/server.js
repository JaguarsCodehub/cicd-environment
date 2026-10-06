import express from 'express';
import { config } from './config.js';
import { initDb, checkHealth, getTasks, createTask, closeDb } from './db.js';

export const app = express();
app.use(express.json());

// Basic request logging
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    if (config.logLevel === 'debug' || req.path !== '/health') {
      console.log(`[HTTP] ${req.method} ${req.path} ${res.statusCode} - ${duration}ms (${config.env})`);
    }
  });
  next();
});

// Liveness & Readiness health probe
app.get('/health', async (req, res) => {
  const dbHealth = await checkHealth();
  const isHealthy = dbHealth.status === 'connected' || dbHealth.status === 'ok';

  const payload = {
    status: isHealthy ? 'healthy' : 'degraded',
    environment: config.env,
    uptimeSeconds: Math.floor(process.uptime()),
    timestamp: new Date().toISOString(),
    database: dbHealth,
  };

  res.status(isHealthy ? 200 : 503).json(payload);
});

// Runtime inspection endpoint
app.get('/api/v1/info', async (req, res) => {
  const dbHealth = await checkHealth();
  res.json({
    appName: config.appName,
    environment: config.env,
    version: config.version,
    commitSha: config.commitSha,
    databaseHost: dbHealth.host || 'unknown',
    databaseStatus: dbHealth.status,
    timestamp: new Date().toISOString(),
    uptimeSeconds: Math.floor(process.uptime()),
  });
});

// List tasks for current environment
app.get('/api/v1/tasks', async (req, res) => {
  try {
    const tasks = await getTasks(config.env);
    res.json({ environment: config.env, count: tasks.length, data: tasks });
  } catch (err) {
    res.status(500).json({ error: 'Failed to retrieve tasks', message: err.message });
  }
});

// Create task in current environment
app.post('/api/v1/tasks', async (req, res) => {
  const { title } = req.body || {};
  if (!title || typeof title !== 'string' || !title.trim()) {
    return res.status(400).json({ error: 'Field "title" is required and must be non-empty string' });
  }

  try {
    const task = await createTask(title.trim(), config.env);
    res.status(201).json({ environment: config.env, data: task });
  } catch (err) {
    res.status(500).json({ error: 'Failed to create task', message: err.message });
  }
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Route not found', path: req.path });
});

let server = null;

export async function startServer(port = config.port) {
  await initDb();
  return new Promise((resolve) => {
    server = app.listen(port, () => {
      console.log(`[SERVER] Started ${config.appName} in [${config.env}] on port ${port}`);
      resolve(server);
    });
  });
}

export async function stopServer() {
  if (server) {
    await new Promise((resolve) => server.close(resolve));
    console.log('[SERVER] HTTP server closed');
  }
  await closeDb();
}

// Graceful shutdown listeners
process.on('SIGTERM', async () => {
  console.log('[SYSTEM] SIGTERM received, initiating graceful shutdown...');
  await stopServer();
  process.exit(0);
});

process.on('SIGINT', async () => {
  console.log('[SYSTEM] SIGINT received, initiating graceful shutdown...');
  await stopServer();
  process.exit(0);
});

// Auto-run if executed directly
if (process.argv[1] && process.argv[1].endsWith('server.js')) {
  startServer();
}
