#!/usr/bin/env bash
# ==============================================================================
# AWS EC2 Provisioning Script for Multi-Environment CI/CD Docker Host
# Recommended OS: Ubuntu 22.04 LTS / 24.04 LTS
# Can be run manually via SSH or passed as EC2 "User Data" during instance launch
# ==============================================================================

set -euo pipefail

echo "=========================================================="
echo " Starting AWS EC2 Provisioning for CI/CD Docker Host..."
echo "=========================================================="

# 1. Update system package index
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y
sudo apt-get upgrade -y

# 2. Install essential system dependencies
sudo apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  git \
  ufw \
  jq

# 3. Add Docker's official GPG key and APT repository
sudo install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
fi

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 4. Install Docker Engine, CLI, and Docker Compose Plugin
sudo apt-get update -y
sudo apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

# 5. Enable and start Docker service
sudo systemctl enable docker
sudo systemctl start docker

# 6. Add default ubuntu user to docker group (avoids needing sudo for docker commands)
if id "ubuntu" &>/dev/null; then
  sudo usermod -aG docker ubuntu
fi

# 7. Create application deployment directory with appropriate ownership
DEPLOY_DIR="/opt/cicd-environment"
sudo mkdir -p "$DEPLOY_DIR"
if id "ubuntu" &>/dev/null; then
  sudo chown -R ubuntu:ubuntu "$DEPLOY_DIR"
fi

# 8. Configure log rotation for Docker to prevent disk exhaustion on EC2 EBS volume
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  }
}
EOF

sudo systemctl restart docker

echo "=========================================================="
echo " Provisioning Complete!"
echo " Docker Version: $(docker --version)"
echo " Docker Compose: $(docker compose version)"
echo " Deployment Dir: $DEPLOY_DIR"
echo "=========================================================="
