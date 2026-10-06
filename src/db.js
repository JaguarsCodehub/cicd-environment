import pg from 'pg';
import { config } from './config.js';

const { Pool } = pg;

let pool = null;
let isInMemoryFallback = false;
const inMemoryTasks = [];

/**
 * Get or initialize the database connection pool
 */
export function getPool() {
  if (!pool && !isInMemoryFallback) {
    try {
      pool = new Pool({
        connectionString: config.databaseUrl,
        connectionTimeoutMillis: 3000,
        idleTimeoutMillis: 10000,
        max: 10,
      });

      pool.on('error', (err) => {
        console.error('[DB] Unexpected error on idle database client', err);
      });
    } catch (err) {
      console.warn('[DB] Failed to instantiate pg Pool, falling back to in-memory mode:', err.message);
      isInMemoryFallback = true;
    }
  }
  return pool;
}

/**
 * Initialize database schema
 */
export async function initDb() {
  const currentPool = getPool();
  if (isInMemoryFallback || !currentPool) {
    console.log('[DB] Running with in-memory database fallback');
    return true;
  }

  try {
    const client = await currentPool.connect();
    try {
      await client.query(`
        CREATE TABLE IF NOT EXISTS tasks (
          id SERIAL PRIMARY KEY,
          title VARCHAR(255) NOT NULL,
          environment VARCHAR(50) NOT NULL,
          created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
        );
      `);
      console.log(`[DB] Schema initialized successfully for environment: ${config.env}`);
      return true;
    } finally {
      client.release();
    }
  } catch (err) {
    console.warn(`[DB] Could not connect to PostgreSQL at ${config.databaseUrl} (${err.message}). Using in-memory fallback.`);
    isInMemoryFallback = true;
    return false;
  }
}

/**
 * Active database liveness probe
 */
export async function checkHealth() {
  if (isInMemoryFallback) {
    return { status: 'ok', mode: 'in-memory-fallback', host: 'in-memory' };
  }

  const currentPool = getPool();
  if (!currentPool) {
    return { status: 'down', mode: 'disconnected' };
  }

  try {
    const client = await currentPool.connect();
    try {
      await client.query('SELECT 1');
      const url = new URL(config.databaseUrl);
      return { status: 'connected', mode: 'postgresql', host: url.hostname };
    } finally {
      client.release();
    }
  } catch (err) {
    return { status: 'down', mode: 'postgresql', error: err.message };
  }
}

/**
 * Fetch tasks for an environment
 */
export async function getTasks(environment = config.env) {
  if (isInMemoryFallback) {
    return inMemoryTasks.filter((t) => !environment || t.environment === environment);
  }

  const currentPool = getPool();
  const res = await currentPool.query(
    'SELECT id, title, environment, created_at FROM tasks WHERE environment = $1 ORDER BY id DESC LIMIT 50',
    [environment]
  );
  return res.rows;
}

/**
 * Insert a new task
 */
export async function createTask(title, environment = config.env) {
  if (isInMemoryFallback) {
    const newTask = {
      id: inMemoryTasks.length + 1,
      title,
      environment,
      created_at: new Date().toISOString(),
    };
    inMemoryTasks.push(newTask);
    return newTask;
  }

  const currentPool = getPool();
  const res = await currentPool.query(
    'INSERT INTO tasks (title, environment) VALUES ($1, $2) RETURNING id, title, environment, created_at',
    [title, environment]
  );
  return res.rows[0];
}

/**
 * Graceful teardown
 */
export async function closeDb() {
  if (pool) {
    await pool.end();
    pool = null;
  }
}
