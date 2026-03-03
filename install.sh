#!/bin/bash

# GitHub Actions Runner Installation Script for Raspberry Pi
# This script sets up a GitHub Actions self-hosted runner with Docker support

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
RUNNER_USER="github-runner"
RUNNER_HOME="/opt/github-runner"
LOCK_FILE_DIR="/tmp"
LOCK_FILE_NAME="raspi-build.lock"

echo -e "${GREEN}🚀 Installing GitHub Actions Runner for Raspberry Pi${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

# Check if we're on ARM architecture (Raspberry Pi)
ARCH=$(uname -m)
if [[ "$ARCH" != "arm"* && "$ARCH" != "aarch64" ]]; then
    echo -e "${YELLOW}Warning: This script is designed for ARM architecture (Raspberry Pi)${NC}"
fi

# Update system
echo -e "${YELLOW}📦 Updating system packages...${NC}"
apt update && apt upgrade -y

# Install required packages
echo -e "${YELLOW}📦 Installing required packages...${NC}"
apt install -y \
    curl \
    wget \
    git \
    jq \
    docker.io \
    docker-compose \
    systemd \
    sudo

# Create runner user
if id "$RUNNER_USER" &>/dev/null; then
    echo -e "${YELLOW}User $RUNNER_USER already exists${NC}"
else
    echo -e "${YELLOW}👤 Creating runner user...${NC}"
    useradd -r -s /bin/bash -d "$RUNNER_HOME" -m "$RUNNER_USER"
fi

# Add user to docker group
usermod -aG docker "$RUNNER_USER"

# Create runner directory
mkdir -p "$RUNNER_HOME"
chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_HOME"

# Copy project files
echo -e "${YELLOW}📁 Setting up project files...${NC}"
cp -r scripts/ config/ systemd/ workflows/ docker/ "$RUNNER_HOME/"
cp .env.template "$RUNNER_HOME/"
chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_HOME"

# Make scripts executable
chmod +x "$RUNNER_HOME/scripts/"*.sh

# Create lock file directory if it doesn't exist
mkdir -p "$LOCK_FILE_DIR"
chown "$RUNNER_USER:$RUNNER_USER" "$LOCK_FILE_DIR"

# Install GitHub Actions Runner
echo -e "${YELLOW}⚙️ Installing GitHub Actions Runner...${NC}"
sudo -u "$RUNNER_USER" bash "$RUNNER_HOME/scripts/setup-runner.sh"

# Install systemd service
echo -e "${YELLOW}🔧 Installing systemd service...${NC}"
cp "$RUNNER_HOME/systemd/github-actions-runner.service" /etc/systemd/system/
systemctl daemon-reload

echo -e "${GREEN}✅ Installation complete!${NC}"
echo
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Copy .env.template to .env and configure your settings:"
echo "   sudo -u $RUNNER_USER cp $RUNNER_HOME/.env.template $RUNNER_HOME/.env"
echo "   sudo -u $RUNNER_USER nano $RUNNER_HOME/.env"
echo
echo "2. Configure the runner with your GitHub repository:"
echo "   sudo -u $RUNNER_USER $RUNNER_HOME/scripts/setup-runner.sh configure"
echo
echo "3. Start the runner service:"
echo "   systemctl enable github-actions-runner"
echo "   systemctl start github-actions-runner"
echo
echo "4. Check service status:"
echo "   systemctl status github-actions-runner"