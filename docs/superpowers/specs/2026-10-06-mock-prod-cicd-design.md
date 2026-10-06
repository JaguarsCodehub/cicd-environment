# Technical Specification: Production-Grade Multi-Environment CI/CD Mock

- **Date:** 2026-10-06
- **Status:** Approved
- **Target System:** `cicd-environment` (Root workspace)

---

## 1. Executive Summary & Goals

This specification defines the complete architecture and implementation details for a mock production-grade CI/CD system spanning three isolated environments: **Development (`dev`)**, **Staging (`staging`)**, and **Production (`main`/`prod`)**.

The implementation satisfies the **"Build Once, Promote Everywhere"** principle:
1. A container image artifact is compiled, tested, and packaged once in CI.
2. The exact same image artifact is deployed across environments, differentiated only by environment variables and secrets.
3. Isolated database instances run per environment (`dev-db`, `staging-db`, `prod-db`).
4. Environments are observable via standard health and inspection probes (`/health`, `/api/v1/info`, `/api/v1/tasks`).
5. A local orchestration harness enables testing environment deployments and promotion locally without requiring external cloud accounts.

---

## 2. System Architecture & Topology

### 2.1 Networking & Port Mapping
All services run locally via Docker Compose using designated network isolation and port bindings:

| Environment | Git Branch | Target Port | Database Service | DB Port (Internal) | Volume Name | Access Level / Gating |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Development** | `dev` | `3001` | `dev-db` (Postgres 16) | `5432` | `dev_db_data` | Continuous / Automatic |
| **Staging** | `staging` | `3002` | `staging-db` (Postgres 16) | `5432` | `staging_db_data` | Pre-prod verification + Auto Integration Tests |
| **Production** | `main` | `3000` | `prod-db` (Postgres 16) | `5432` | `prod_db_data` | **Manual Approval Gate** (Required Reviewer) |

### 2.2 Network Topology Diagram
```text
Host Network
 ├── :3001 ──► [ Dev API Container ]      ──► [ dev-db (PostgreSQL) ]
 ├── :3002 ──► [ Staging API Container ]  ──► [ staging-db (PostgreSQL) ]
 └── :3000 ──► [ Production Container ]   ──► [ prod-db (PostgreSQL) ]
```

---

## 3. Application Specifications

The core application is an Express-based Node.js service (`src/server.js`) configured via 12-factor environment variables.

### 3.1 Endpoints
- `GET /health`:
  - Returns `200 OK` with `{ status: "ok", uptime: number, dbStatus: "connected" }`.
  - Performs active DB heartbeat ping (`SELECT 1`). Returns `503 Service Unavailable` if database is unreachable.
- `GET /api/v1/info`:
  - Returns metadata:
    ```json
    {
      "environment": "development" | "staging" | "production",
      "version": "1.0.0",
      "commitSha": "abc1234",
      "databaseHost": "dev-db",
      "timestamp": "2026-10-06T10:00:00.000Z"
    }
    ```
- `GET /api/v1/tasks`: Returns list of stored tasks from the environment's isolated database.
- `POST /api/v1/tasks`: Creates a task `{ title, description }` to verify persistent storage writes in that specific tier.

### 3.2 Database Schema & Auto-Migration
A simple initialization script runs on application startup:
```sql
CREATE TABLE IF NOT EXISTS tasks (
  id SERIAL PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  environment VARCHAR(50) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

### 3.3 Security & Runtime Hardening
- Production profile runs with `NODE_ENV=production`.
- Docker runtime runs as non-root user (`node`).
- Graceful shutdown handling (`SIGINT` and `SIGTERM`) closes DB connections and server listeners within a 10s timeout window.

---

## 4. Containerization & Multi-Stage Dockerfile

### 4.1 Multi-Stage `Dockerfile`
- **Stage 1 (`builder`)**:
  - Base: `node:20-alpine`
  - Installs all dependencies (`npm ci`).
  - Runs unit tests (`npm test`).
- **Stage 2 (`runner`)**:
  - Base: `node:20-alpine`
  - Installs production-only dependencies (`npm ci --omit=dev`).
  - Sets `USER node`.
  - Exposes port `3000` (mapped to host ports dynamically).
  - Healthcheck instruction verifying `curl -f http://localhost:3000/health || exit 1`.

---

## 5. Docker Compose Environment Profiles

A single `docker-compose.yml` defining environment profiles (`dev`, `staging`, `prod`):
- `profile: dev`:
  - Starts `dev-db` and `app-dev`.
  - Injects environment from `.env.development`.
- `profile: staging`:
  - Starts `staging-db` and `app-staging`.
  - Injects environment from `.env.staging`.
- `profile: prod`:
  - Starts `prod-db` and `app-prod`.
  - Injects environment from `.env.production`.

---

## 6. CI/CD GitHub Actions Pipeline (`.github/workflows/deploy.yml`)

### 6.1 Workflow Triggers & Concurrency
- Triggers on `push` to `dev`, `staging`, and `main`.
- Concurrency group: `deploy-${{ github.ref }}` with `cancel-in-progress: true`.

### 6.2 Pipeline Jobs
1. **`ci` (Build, Test & Package)**:
   - Sets up Node.js 20.
   - Runs `npm ci` and `npm test`.
   - Builds Docker image tagged with `cicd-demo:${{ github.sha }}` and `cicd-demo:latest`.
   - Exports image artifact or saves tarball to GitHub Actions cache/artifact store.
2. **`deploy-dev` (Development Tier)**:
   - Condition: `github.ref == 'refs/heads/dev'`
   - GitHub Environment: `development`
   - Executes deployment script with `dev` config and verifies `/health`.
3. **`deploy-staging` (Staging Tier)**:
   - Condition: `github.ref == 'refs/heads/staging'`
   - GitHub Environment: `staging`
   - Executes deployment, validates health, and runs automated integration test suite (`npm run test:integration`).
4. **`deploy-prod` (Production Tier)**:
   - Condition: `github.ref == 'refs/heads/main'`
   - GitHub Environment: `production` (Configured with **Required Reviewers**).
   - Pauses for approval.
   - Executes production deployment and validates liveness probes.

---

## 7. Local Simulation Harness (`scripts/deploy-env.ps1` & `scripts/deploy-env.sh`)

To allow instant testing without external dependencies, local scripts are provided:
- `./scripts/deploy-env.ps1 -Environment dev` -> Brings up dev containers on port 3001, runs migrations, verifies health.
- `./scripts/deploy-env.ps1 -Environment staging` -> Brings up staging containers on port 3002, runs smoke tests.
- `./scripts/deploy-env.ps1 -Environment prod` -> Prompts interactive confirmation (mocking approval gate), boots prod stack on port 3000.
- `./scripts/deploy-env.ps1 -Status` -> Queries and outputs JSON health status for all 3 environments.
- `./scripts/deploy-env.ps1 -TearDown` -> Gracefully stops all containers and volumes.

---

## 8. Directory Structure

```text
cicd-environment/
├── .github/
│   └── workflows/
│       └── deploy.yml
├── docker/
│   └── init-db.sql
├── scripts/
│   ├── deploy-env.ps1
│   ├── deploy-env.sh
│   └── smoke-test.js
├── src/
│   ├── config.js
│   ├── db.js
│   └── server.js
├── test/
│   ├── app.test.js
│   └── integration.test.js
├── .env.development
├── .env.staging
├── .env.production
├── .env.example
├── .gitignore
├── Dockerfile
├── docker-compose.yml
├── package.json
└── README.md
```

---

## 9. Verification & Success Criteria

1. `npm test` passes in isolation.
2. Building Docker image succeeds without warnings.
3. Running `deploy-env.ps1 -Environment <dev|staging|prod>` brings up the expected container with correct environment variables and isolated database.
4. Calling `/health` and `/api/v1/info` returns 200 OK and accurate environment metadata.
5. Pushing commits to `dev`, `staging`, and `main` executes the corresponding CI/CD pipeline steps with environment protection rules on GitHub.
