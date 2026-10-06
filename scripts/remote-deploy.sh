#!/usr/bin/env bash
# ==============================================================================
# Remote Deployment Script for AWS EC2 Target
# Usage: ./scripts/remote-deploy.sh <dev|staging|prod> <ec2_host> [ec2_user]
# ==============================================================================

set -euo pipefail

ENVIRONMENT="${1:-}"
EC2_HOST="${2:-}"
EC2_USER="${3:-ubuntu}"
DEPLOY_DIR="/opt/cicd-environment"

if [[ -z "$ENVIRONMENT" || -z "$EC2_HOST" ]]; then
  echo "Usage: $0 <dev|staging|prod> <ec2_host> [ec2_user]"
  exit 1
fi

case "$ENVIRONMENT" in
  dev) PORT=3001 ;;
  staging) PORT=3002 ;;
  prod) PORT=3000 ;;
  *)
    echo "Error: Invalid environment '$ENVIRONMENT'. Must be dev, staging, or prod."
    exit 1
    ;;
esac

echo "=========================================================="
echo " Initiating Remote Deployment to AWS EC2: $EC2_HOST"
echo " Environment: $ENVIRONMENT (Target Port: $PORT)"
echo " Remote User: $EC2_USER"
echo "=========================================================="

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=15"

# 1. Prepare target directory on EC2
echo "• Creating remote deployment directory..."
ssh $SSH_OPTS "${EC2_USER}@${EC2_HOST}" "mkdir -p ${DEPLOY_DIR}"

# 2. Transfer Docker Compose, Environment Config, and Built Image
echo "• Syncing docker-compose.yml and environment files..."
scp $SSH_OPTS docker-compose.yml "${EC2_USER}@${EC2_HOST}:${DEPLOY_DIR}/docker-compose.yml"
scp $SSH_OPTS ".env.${ENVIRONMENT}" "${EC2_USER}@${EC2_HOST}:${DEPLOY_DIR}/.env.${ENVIRONMENT}"

if [ -f "dist/app-image.tar" ]; then
  echo "• Transferring compiled image artifact (dist/app-image.tar)..."
  scp $SSH_OPTS dist/app-image.tar "${EC2_USER}@${EC2_HOST}:${DEPLOY_DIR}/app-image.tar"
fi

# 3. Load image, boot container stack, and verify local container readiness on EC2
echo "• Loading image and starting container stack on EC2..."
ssh $SSH_OPTS "${EC2_USER}@${EC2_HOST}" << EOF
  set -e
  cd ${DEPLOY_DIR}

  if [ -f "app-image.tar" ]; then
    echo "  Loading Docker image artifact..."
    docker load -i app-image.tar
  fi

  echo "  Starting environment profile '${ENVIRONMENT}'..."
  docker compose --profile "${ENVIRONMENT}" up -d

  echo "  Waiting for internal healthcheck readiness on port ${PORT}..."
  timeout 60 bash -c 'until curl -s -f http://localhost:${PORT}/health > /dev/null; do sleep 2; done'
  echo "  Container is healthy on EC2!"
EOF

# 4. Verify remote public endpoint with automated smoke tests
echo "• Verifying public EC2 endpoint from runner: http://${EC2_HOST}:${PORT}..."
node scripts/smoke-test.js "http://${EC2_HOST}:${PORT}"

echo "=========================================================="
echo " Remote Deployment and Smoke Verification Complete!"
echo " Service Endpoint: http://${EC2_HOST}:${PORT}"
echo " Health Probe:    http://${EC2_HOST}:${PORT}/health"
echo " Info Endpoint:   http://${EC2_HOST}:${PORT}/api/v1/info"
echo "=========================================================="
