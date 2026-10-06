# AWS EC2 Multi-Environment CI/CD Deployment Guide

This guide walks through configuring an **AWS EC2 instance** to host all three isolated tiers (**Development**, **Staging**, and **Production**) using Docker and Docker Compose, connected directly to your GitHub Actions pipeline.

---

## 1. AWS EC2 Instance Provisioning

### Recommended Specifications
- **AMI:** Ubuntu Server 24.04 LTS or 22.04 LTS (64-bit x86)
- **Instance Type:** `t3.small` (2 vCPU, 2 GB RAM) or `t3.medium` (4 GB RAM recommended to comfortably run 3 Node app containers + 3 PostgreSQL database containers)
- **Storage:** 20 GB – 30 GB gp3 EBS Volume
- **Key Pair:** Create or select an existing RSA key pair (e.g., `cicd-key.pem`) and download the `.pem` file.

### Security Group Inbound Rules
Configure your EC2 Security Group with the following inbound rules:

| Type | Port Range | Protocol | Source | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **SSH** | `22` | TCP | `0.0.0.0/0` (or your IP) | Management & GitHub Actions deploy runner |
| **Custom TCP** | `3001` | TCP | `0.0.0.0/0` | Development API endpoint |
| **Custom TCP** | `3002` | TCP | `0.0.0.0/0` | Staging API endpoint |
| **Custom TCP** | `3000` | TCP | `0.0.0.0/0` | Production API endpoint |

*(Note: In production environments, ports 3001 and 3002 can be restricted to VPN/internal IPs, or routed via an Nginx reverse proxy on port 80/443).*

---

## 2. Server Setup (One-Time Execution)

### Option A: Using EC2 User Data (Automatic at Launch)
Paste the contents of [`scripts/ec2-setup.sh`](./scripts/ec2-setup.sh) into the **User Data** field under **Advanced details** when launching the instance.

### Option B: Running Manually via SSH
Connect to your running EC2 instance:

```bash
chmod 400 cicd-key.pem
ssh -i cicd-key.pem ubuntu@<EC2_PUBLIC_IP>
```

Clone the repository or run the setup script:

```bash
curl -fsSL https://raw.githubusercontent.com/JaguarsCodehub/cicd-environment/main/scripts/ec2-setup.sh | bash
```

Verify that Docker is operational without `sudo`:

```bash
docker --version
docker compose version
```

---

## 3. GitHub Repository Secrets Configuration

Navigate to your GitHub repository $\rightarrow$ **Settings** $\rightarrow$ **Secrets and variables** $\rightarrow$ **Actions** $\rightarrow$ **New repository secret**:

| Secret Name | Description | Example Value |
| :--- | :--- | :--- |
| `EC2_HOST` | The public IPv4 address or Public IPv4 DNS of your EC2 instance | `54.210.123.45` |
| `EC2_USER` | The default SSH user | `ubuntu` |
| `EC2_SSH_KEY` | Entire contents of your private key `.pem` file (including `-----BEGIN RSA PRIVATE KEY-----` and `-----END RSA PRIVATE KEY-----`) | `-----BEGIN OPENSSH PRIVATE KEY----- ... -----END OPENSSH PRIVATE KEY-----` |

*(Tip: You can set these as **Repository Secrets** to apply across all branches, or scope them under **Environment Secrets** in GitHub Environments if you ever split across distinct EC2 instances).*

---

## 4. GitHub Environments Setup

Navigate to **Settings** $\rightarrow$ **Environments**:

1. **`development`**:
   - Deployment branches: `Selected branches` $\rightarrow$ Add `dev`.
2. **`staging`**:
   - Deployment branches: `Selected branches` $\rightarrow$ Add `staging`.
3. **`production`**:
   - Deployment branches: `Selected branches` $\rightarrow$ Add `main`.
   - Deployment protection rules: Check **Required reviewers** and add your account.

---

## 5. Deployment & Promotion Walkthrough

### Scenario 1: Feature Commit on `dev`
```bash
git checkout -b dev
git add . && git commit -m "feat: updated endpoint response"
git push -u origin dev
```
**Outcome:**
1. CI builds and tests the Docker image artifact once.
2. `deploy-dev` SSHs to EC2, loads the image, boots `cicd-app-dev` on port `3001`, and spins up `cicd-dev-db`.
3. Live URL: `http://<EC2_PUBLIC_IP>:3001/api/v1/info`

### Scenario 2: Promote to `staging`
```bash
git checkout staging
git merge dev
git push origin staging
```
**Outcome:**
1. CI verifies artifact.
2. `deploy-staging` rolls out to port `3002` on EC2, connects to `cicd-staging-db`, and executes the automated smoke test suite.
3. Live URL: `http://<EC2_PUBLIC_IP>:3002/api/v1/info`

### Scenario 3: Promote to `production` (Approval Gate)
```bash
git checkout main
git merge staging
git push origin main
```
**Outcome:**
1. CI builds and passes.
2. Workflow pauses: **Waiting for review: production**.
3. You click **Review deployments** $\rightarrow$ **Approve and deploy**.
4. Pipeline deploys `cicd-app-prod` on port `3000` with `cicd-prod-db` and verifies health.
5. Live URL: `http://<EC2_PUBLIC_IP>:3000/api/v1/info`

---

## 6. Inspecting Containers on EC2

SSH into your EC2 instance anytime to inspect containers and database volumes:

```bash
# List all running environment containers
docker ps

# View logs for a specific tier
docker logs -f cicd-app-dev
docker logs -f cicd-app-staging
docker logs -f cicd-app-prod

# Inspect PostgreSQL databases inside containers
docker exec -it cicd-dev-db psql -U dev_user -d dev_db -c "SELECT * FROM tasks;"
docker exec -it cicd-staging-db psql -U staging_user -d staging_db -c "SELECT * FROM tasks;"
docker exec -it cicd-prod-db psql -U prod_user -d prod_db -c "SELECT * FROM tasks;"

# Inspect persistent volumes on EBS
docker volume ls
```
