# CI/CD Multi-Branch & Multi-Environment Implementation Plan

This document outlines the architectural blueprint, repository layout, environment protection configurations, and operational verification procedures for a multi-branch CI/CD workflow across `dev`, `staging`, and `main` (production).

---

## 1. Architectural Overview & Promotion Flow

The system employs a **Build Once, Promote Everywhere** pattern. Code changes progress sequentially across branches, and deployments target their respective isolated environments with environment-scoped runtime parameters.

```text
[ Feature Branch ]
       │
       ▼ (Pull Request)
[ dev Branch ] ──────────► Auto-deploy to "development" environment
       │
       ▼ (Merge Pull Request)
[ staging Branch ] ──────► Auto-deploy to "staging" environment + Integration Tests
       │
       ▼ (Merge Pull Request)
[ main Branch ] ─────────► [Manual Approval Gate] ──► Deploy to "production"
```

---

## 2. Environment & Promotion Topology

| Layer | Git Branch | Deployment Target | Approval Required | Variable Scope |
| :--- | :--- | :--- | :--- | :--- |
| **Development** | `dev` | `development` | None (Continuous) | `ENV_NAME=development`<br>`DATABASE_HOST=dev-db.internal` |
| **Staging** | `staging` | `staging` | None (Pre-prod staging) | `ENV_NAME=staging`<br>`DATABASE_HOST=staging-db.internal` |
| **Production** | `main` | `production` | **Yes** (Required Reviewer) | `ENV_NAME=production`<br>`DATABASE_HOST=prod-cluster.internal` |

---

## 3. Project Directory Structure

```text
cicd-demo/
├── .github/
│   └── workflows/
│       └── deploy.yml        # Unified CI/CD workflow with environment gates
├── test/
│   └── app.test.js           # Lightweight automated verification suite
├── .gitignore
├── package.json              # Project manifest and test runner configuration
└── README.md
```

---

## 4. Phase-by-Phase Implementation Plan

### Phase 1: Local Project Initialization

1. **Initialize Git Repository and Node.js Project:**
   ```bash
   mkdir cicd-demo
   cd cicd-demo
   git init -b main
   npm init -y
   ```

2. **Configure `package.json`:**
   Add native Node.js test runner execution:
   ```json
   {
     "name": "cicd-demo",
     "version": "1.0.0",
     "type": "module",
     "scripts": {
       "test": "node --test"
     }
   }
   ```

3. **Create Basic Test Suite (`test/app.test.js`):**
   ```javascript
   import test from 'node:test';
   import assert from 'node:assert';

   test('Core smoke check', () => {
     assert.strictEqual(1 + 1, 2);
   });
   ```

4. **Add `.gitignore`:**
   ```text
   node_modules/
   .env
   ```

---

### Phase 2: Workflow Pipeline Configuration

Create `.github/workflows/deploy.yml` with concurrency control, sequential job dependencies, and native GitHub `environment` scopes.

```yaml
name: CI/CD Multi-Environment Pipeline

on:
  push:
    branches:
      - dev
      - staging
      - main

concurrency:
  group: deploy-${{ github.ref }}
  cancel-in-progress: true

jobs:
  ci:
    name: Build & Test
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 20

      - name: Run Test Suite
        run: npm test

  deploy-dev:
    name: Deploy to Development
    needs: ci
    if: github.ref == 'refs/heads/dev'
    environment:
      name: development
      url: https://dev.api.example.com
    runs-on: ubuntu-latest
    steps:
      - name: Execute Dev Deployment
        run: |
          echo "Deploying to: ${{ vars.ENV_NAME }}"
          echo "Database Host: ${{ vars.DATABASE_HOST }}"
          echo "Commit SHA: ${{ github.sha }}"

  deploy-staging:
    name: Deploy to Staging
    needs: ci
    if: github.ref == 'refs/heads/staging'
    environment:
      name: staging
      url: https://staging.api.example.com
    runs-on: ubuntu-latest
    steps:
      - name: Execute Staging Deployment
        run: |
          echo "Deploying to: ${{ vars.ENV_NAME }}"
          echo "Database Host: ${{ vars.DATABASE_HOST }}"
          echo "Commit SHA: ${{ github.sha }}"

  deploy-prod:
    name: Deploy to Production
    needs: ci
    if: github.ref == 'refs/heads/main'
    environment:
      name: production
      url: https://api.example.com
    runs-on: ubuntu-latest
    steps:
      - name: Execute Production Deployment
        run: |
          echo "Deploying to: ${{ vars.ENV_NAME }}"
          echo "Database Host: ${{ vars.DATABASE_HOST }}"
          echo "Commit SHA: ${{ github.sha }}"
```

Commit and register the initial baseline:
```bash
git add .
git commit -m "feat: setup project baseline and multi-environment pipeline"
```

---

### Phase 3: Remote Repository & Branch Topology Setup

1. **Create GitHub Repository:**
   - Create a new repository on GitHub named `cicd-demo`.
   - Ensure the repository visibility is **Public** (required on GitHub Free accounts to use Environment protection rules and reviewer gates).

2. **Push Main Branch:**
   ```bash
   git remote add origin https://github.com/<YOUR_USERNAME>/cicd-demo.git
   git push -u origin main
   ```

3. **Cut and Push Staging and Dev Branches:**
   ```bash
   # Branch 2: staging
   git checkout -b staging
   git push -u origin staging

   # Branch 3: dev
   git checkout -b dev
   git push -u origin dev
   ```

---

### Phase 4: GitHub Environment & Security Configuration

Navigate to **Repository Settings** $\rightarrow$ **Environments** on GitHub and configure each tier:

#### 1. `development` Environment
- Click **New environment** $\rightarrow$ Enter `development`.
- **Deployment branches:** Set to **Selected branches** $\rightarrow$ Add `dev`.
- **Environment variables:**
  - `ENV_NAME`: `development`
  - `DATABASE_HOST`: `dev-db.internal`

#### 2. `staging` Environment
- Click **New environment** $\rightarrow$ Enter `staging`.
- **Deployment branches:** Set to **Selected branches** $\rightarrow$ Add `staging`.
- **Environment variables:**
  - `ENV_NAME`: `staging`
  - `DATABASE_HOST`: `staging-db.internal`

#### 3. `production` Environment
- Click **New environment** $\rightarrow$ Enter `production`.
- **Deployment protection rules:**
  - Enable **Required reviewers**.
  - Add your GitHub account username or deployment leads.
- **Deployment branches:** Set to **Selected branches** $\rightarrow$ Add `main`.
- **Environment variables:**
  - `ENV_NAME`: `production`
  - `DATABASE_HOST`: `prod-cluster.internal`

---

### Phase 5: Verification & Promotion Testing

#### Scenario A: Dev Auto-Deployment
1. Make a minor modification while checked out on `dev`:
   ```bash
   git checkout dev
   echo "// testing dev trigger" >> test/app.test.js
   git commit -am "test: verify automated development deployment"
   git push origin dev
   ```
2. **Expected Behavior:** `ci` runs and passes. `deploy-dev` executes immediately and outputs development variables. `deploy-staging` and `deploy-prod` are skipped.

#### Scenario B: Staging Promotion
1. Promote the change into `staging`:
   ```bash
   git checkout staging
   git merge dev
   git push origin staging
   ```
2. **Expected Behavior:** `ci` passes. `deploy-staging` executes without manual gate and logs `staging-db.internal`.

#### Scenario C: Production Gated Promotion
1. Promote the change into `main`:
   ```bash
   git checkout main
   git merge staging
   git push origin main
   ```
2. **Expected Behavior:**
   - `ci` succeeds.
   - The workflow pauses at `deploy-prod` with status: `Waiting for review: production`.
   - Reviewer clicks **Review deployments**, selects **production**, and clicks **Approve and deploy**.
   - Deployment proceeds and outputs production environment variables.

---

## 5. Security & Operational Checklist

- [ ] Branch protection enabled on `main` to prevent unreviewed direct pushes.
- [ ] Concurrency group enabled to prevent out-of-order race conditions on concurrent pushes.
- [ ] Immutable commit SHAs used to track and trace build artifacts across stages.
- [ ] Database credentials and API tokens stored strictly in Environment Secrets, never committed to Git.