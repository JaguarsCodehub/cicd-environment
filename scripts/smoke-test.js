/**
 * Automated Smoke Verification Suite
 * Usage: node scripts/smoke-test.js [targetUrl]
 */

const targetUrl = process.argv[2] || process.env.TARGET_URL || 'http://localhost:3000';

async function runSmokeTests() {
  console.log(`\n=================================================`);
  console.log(`[SMOKE TEST] Initiating verification against: ${targetUrl}`);
  console.log(`=================================================`);

  let passed = 0;
  let failed = 0;

  async function check(name, fn) {
    process.stdout.write(`• Checking ${name}... `);
    try {
      await fn();
      console.log(`\x1b[32mPASSED\x1b[0m`);
      passed++;
    } catch (err) {
      console.log(`\x1b[31mFAILED\x1b[0m`);
      console.error(`  Error: ${err.message}`);
      failed++;
    }
  }

  // 1. Health Probe
  await check('Liveness & Readiness probe (/health)', async () => {
    const res = await fetch(`${targetUrl}/health`);
    if (!res.ok) throw new Error(`Status ${res.status}`);
    const data = await res.json();
    if (data.status !== 'healthy') throw new Error(`Degraded status: ${JSON.stringify(data)}`);
  });

  // 2. Info Probe
  let envReported = '';
  await check('Runtime inspection probe (/api/v1/info)', async () => {
    const res = await fetch(`${targetUrl}/api/v1/info`);
    if (!res.ok) throw new Error(`Status ${res.status}`);
    const data = await res.json();
    envReported = data.environment;
    if (!data.environment || !data.version || !data.commitSha) {
      throw new Error(`Incomplete metadata: ${JSON.stringify(data)}`);
    }
    console.log(`\n  [Info] Environment: \x1b[36m${data.environment}\x1b[0m | Commit: ${data.commitSha} | DB: ${data.databaseHost} (${data.databaseStatus})`);
  });

  // 3. Database Write & Read Verification
  await check('Database write persistence (/api/v1/tasks)', async () => {
    const taskTitle = `Synthetic smoke test ping @ ${new Date().toISOString()}`;
    const postRes = await fetch(`${targetUrl}/api/v1/tasks`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title: taskTitle }),
    });
    if (postRes.status !== 201) throw new Error(`Create task failed with status ${postRes.status}`);
    const created = await postRes.json();
    if (!created.data || !created.data.id) throw new Error('Task ID missing in response');

    const getRes = await fetch(`${targetUrl}/api/v1/tasks`);
    if (!getRes.ok) throw new Error(`List tasks failed with status ${getRes.status}`);
    const list = await getRes.json();
    const found = list.data.some((t) => t.id === created.data.id);
    if (!found) throw new Error(`Created task ${created.data.id} not found in database listing`);
  });

  console.log(`\n-------------------------------------------------`);
  console.log(`Summary: ${passed} passed, ${failed} failed`);
  console.log(`-------------------------------------------------\n`);

  if (failed > 0) {
    process.exit(1);
  }
}

runSmokeTests().catch((err) => {
  console.error('[FATAL] Smoke test runner failed unexpectedly:', err);
  process.exit(1);
});
