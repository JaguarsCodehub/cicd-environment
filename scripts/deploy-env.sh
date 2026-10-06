#!/usr/bin/env bash
set -e

ENV_TARGET="$1"

show_header() {
  echo -e "\033[36m\n================================================="
  echo -e "   CI/CD MULTI-ENVIRONMENT ORCHESTRATION CLI     "
  echo -e "=================================================\n\033[0m"
}

check_status() {
  local name="$1"
  local port="$2"
  if curl -s -f "http://localhost:$port/health" > /dev/null 2>&1; then
    local info=$(curl -s "http://localhost:$port/api/v1/info")
    echo -e "[$name] (Port $port): \033[32mHEALTHY\033[0m | $info"
  else
    echo -e "[$name] (Port $port): \033[90mOFFLINE / UNREACHABLE\033[0m"
  fi
}

show_header

if [ "$ENV_TARGET" == "status" ]; then
  echo -e "\033[33mInspecting Environment Status across all tiers:\n\033[0m"
  check_status "Development" 3001
  check_status "Staging    " 3002
  check_status "Production " 3000
  echo ""
  exit 0
fi

if [ "$ENV_TARGET" == "teardown" ]; then
  echo -e "\033[33m[TEARDOWN] Stopping all containers and volumes...\033[0m"
  docker compose --profile dev --profile staging --profile prod down -v
  echo -e "\033[32m[TEARDOWN] All environments stopped.\033[0m"
  exit 0
fi

if [ -z "$ENV_TARGET" ] || [[ ! "$ENV_TARGET" =~ ^(dev|staging|prod)$ ]]; then
  echo -e "\033[31mUsage: ./scripts/deploy-env.sh <dev|staging|prod|status|teardown> [--build]\033[0m"
  exit 1
fi

case "$ENV_TARGET" in
  dev) PORT=3001 ;;
  staging) PORT=3002 ;;
  prod) PORT=3000 ;;
esac

if [ "$ENV_TARGET" == "prod" ]; then
  echo -e "\033[35m================================================="
  echo -e " [GATE] PRODUCTION ENVIRONMENT APPROVAL REQUIRED  "
  echo -e "=================================================\033[0m"
  read -p "Approve and promote to PRODUCTION? (type 'yes' to proceed): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo -e "\033[31m[GATE DENIED] Production deployment cancelled.\033[0m"
    exit 1
  fi
fi

BUILD_FLAG=""
if [ "$2" == "--build" ]; then
  BUILD_FLAG="--build"
fi

echo -e "\033[36m[DEPLOY] Deploying tier '$ENV_TARGET' on port $PORT...\033[0m"
docker compose --profile "$ENV_TARGET" up -d $BUILD_FLAG

echo -e "\033[33m[WAIT] Waiting for container health probe...\033[0m"
HEALTHY=0
for i in {1..15}; do
  sleep 2
  if curl -s -f "http://localhost:$PORT/health" > /dev/null 2>&1; then
    HEALTHY=1
    break
  fi
  echo "  Attempt $i/15: waiting..."
done

if [ "$HEALTHY" -ne 1 ]; then
  echo -e "\033[31m[ERROR] Healthcheck timed out on port $PORT\033[0m"
  docker compose --profile "$ENV_TARGET" logs --tail 50
  exit 1
fi

echo -e "\033[32m[SUCCESS] Tier '$ENV_TARGET' is online on http://localhost:$PORT!\033[0m\n"

echo -e "\033[36m[VERIFY] Running automated post-deployment smoke verification suite...\033[0m"
node scripts/smoke-test.js "http://localhost:$PORT"

echo -e "\033[32m>>> Deployment completed successfully for [$ENV_TARGET] <<<\033[0m\n"
