# Production-Grade Multi-Environment CI/CD Mock

This repository demonstrates an enterprise-grade CI/CD multi-branch and multi-environment architecture spanning **Development (`dev`)**, **Staging (`staging`)**, and **Production (`main`)**.

It implements the **"Build Once, Promote Everywhere"** pattern: an immutable container image is built and verified once in CI, then promoted sequentially across environments with isolated PostgreSQL databases, distinct environment variables, automated health probes, and production approval gates.

---

## 1. System Architecture & Topology

```text
Host / Runner Network
 ├── :3001 ──► [ Dev API Container ]      ──► [ dev-db (PostgreSQL) ]
 ├── :3002 ──► [ Staging API Container ]  ──► [ staging-db (PostgreSQL) ]
 └── :3000 ──► [ Production Container ]   ──► [ prod-db (PostgreSQL) ]
```

| Layer | Branch | Host Port | Database Container | Verification & Gating |
| :--- | :--- | :--- | :--- | :--- |
| **Development** | `dev` | `3001` | `cicd-dev-db` (5432) | Continuous deployment, debug logs, health check |
| **Staging** | `staging` | `3002` | `cicd-staging-db` (5432) | Automated deployment, pre-prod parity, smoke verification suite |
| **Production** | `main` | `3000` | `cicd-prod-db` (5432) | **Manual Reviewer Approval Gate**, hardened configuration |

> [!TIP]
> **Deploying to AWS EC2:** See the comprehensive [AWS EC2 Deployment Guide](aws_ec2_deployment_guide.md) for full instructions on provisioning an Ubuntu EC2 instance, security group settings, and linking GitHub Secrets (`EC2_HOST`, `EC2_USER`, `EC2_SSH_KEY`).

---

## 2. Quickstart & Local Orchestration

You can simulate and test the entire multi-environment lifecycle locally using the provided deployment CLI without pushing to GitHub.

### Prerequisites
- Node.js 20+
- Docker & Docker Compose

### Run Unit and Integration Tests Locally
```bash
npm install
npm test
npm run test:integration
```

### Local Environment Orchestration (PowerShell / Windows)
```powershell
# Deploy Development tier (:3001)
.\scripts\deploy-env.ps1 -Environment dev

# Deploy Staging tier (:3002) + run smoke suite
.\scripts\deploy-env.ps1 -Environment staging

# Deploy Production tier (:3000) with interactive approval gate
.\scripts\deploy-env.ps1 -Environment prod

# Inspect health and metadata across all 3 tiers
.\scripts\deploy-env.ps1 -Status

# Teardown all containers and volumes
.\scripts\deploy-env.ps1 -TearDown
```

### Local Environment Orchestration (Bash / Linux / macOS)
```bash
./scripts/deploy-env.sh dev
./scripts/deploy-env.sh staging
./scripts/deploy-env.sh prod
./scripts/deploy-env.sh status
./scripts/deploy-env.sh teardown
```

---

## 3. API Endpoints

Each deployed environment exposes:

- `GET /health`: Liveness & readiness probe verifying application uptime and PostgreSQL connectivity (`SELECT 1`).
- `GET /api/v1/info`: Metadata inspection endpoint returning current environment, version, commit SHA, database host, and timestamp.
- `GET /api/v1/tasks`: Lists environment-scoped tasks from the isolated database.
- `POST /api/v1/tasks`: Creates a task in the environment's isolated database.

---

## 4. GitHub Actions Multi-Environment Pipeline

The pipeline in [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml) operates as follows:

```text
[ Push Event: dev / staging / main ]
                   │
                   ▼
     ┌───────────────────────────┐
     │  Job: ci (Build & Test)   │
     │  - Unit tests             │
     │  - Integration tests      │
     │  - Multi-stage build      │
     │  - Export docker image    │
     └─────────────┬─────────────┘
                   │
       ┌───────────┼───────────┐
       ▼           ▼           ▼
[ Branch: dev ] [ Branch: staging ] [ Branch: main ]
       │           │           │
       ▼           ▼           ▼
 ┌───────────┐ ┌───────────┐ ┌──────────────────────┐
 │deploy-dev │ │deploy-    │ │deploy-prod           │
 │  (Auto)   │ │staging    │ │  (Manual Approval    │
 │           │ │ (Auto +   │ │   Gate Required)     │
 │           │ │  Smoke)   │ │                      │
 └───────────┘ └───────────┘ └──────────────────────┘
```

---

## 5. Setting up GitHub Environments

To enforce deployment gates on GitHub:

1. Navigate to **Settings** $\rightarrow$ **Environments** on your GitHub repository.
2. Create three environments:
   - `development`:
     - Deployment branches: `dev`
   - `staging`:
     - Deployment branches: `staging`
   - `production`:
     - Deployment branches: `main`
     - Deployment protection rules: Check **Required reviewers** and add your GitHub account.

---

## 6. Git Promotion Workflow

```bash
# 1. Feature work on dev
git checkout -b dev
# Make changes
git add . && git commit -m "feat: new feature"
git push origin dev
# -> Triggers CI and auto-deploys to development

# 2. Promote to staging
git checkout -b staging
git merge dev
git push origin staging
# -> Triggers CI and auto-deploys to staging with automated smoke tests

# 3. Promote to production
git checkout main
git merge staging
git push origin main
# -> Pauses for reviewer approval in GitHub, then deploys to production
```
