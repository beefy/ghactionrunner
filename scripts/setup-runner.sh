#!/bin/bash

# GitHub Actions Runner Setup Script
set -e

# Load environment variables
if [ -f "$(dirname "$0")/../.env" ]; then
    source "$(dirname "$0")/../.env"
else
    echo "Warning: .env file not found. Please copy .env.template to .env and configure it."
    if [ "$1" != "configure" ]; then
        exit 1
    fi
fi

RUNNER_HOME="/opt/github-runner"
RUNNER_VERSION="2.314.1"  # Update this to latest version as needed

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

download_and_install_runner() {
    echo -e "${YELLOW}📥 Downloading GitHub Actions Runner...${NC}"
    
    cd "$RUNNER_HOME"
    
    # Detect architecture
    ARCH=$(uname -m)
    case $ARCH in
        aarch64) RUNNER_ARCH="linux-arm64" ;;
        armv7l) RUNNER_ARCH="linux-arm" ;;
        x86_64) RUNNER_ARCH="linux-x64" ;;
        *) echo -e "${RED}Unsupported architecture: $ARCH${NC}"; exit 1 ;;
    esac
    
    # Download runner
    RUNNER_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
    
    if [ ! -f "actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz" ]; then
        wget "$RUNNER_URL" -O "actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
    fi
    
    # Extract
    if [ ! -d "bin" ]; then
        tar xzf "actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
    fi
    
    # Install dependencies
    sudo ./bin/installdependencies.sh || true
    
    echo -e "${GREEN}✅ Runner downloaded and extracted${NC}"
}

configure_runner() {
    echo -e "${YELLOW}⚙️ Configuring GitHub Actions Runner...${NC}"
    
    if [ -z "$GITHUB_TOKEN" ] || [ -z "$GITHUB_REPOSITORY" ]; then
        echo -e "${RED}Please set GITHUB_TOKEN and GITHUB_REPOSITORY in .env file${NC}"
        exit 1
    fi
    
    cd "$RUNNER_HOME"
    
    # Get registration token
    echo -e "${YELLOW}🔑 Getting registration token...${NC}"
    REG_TOKEN=$(curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runners/registration-token" | jq -r .token)
    
    if [ "$REG_TOKEN" = "null" ] || [ -z "$REG_TOKEN" ]; then
        echo -e "${RED}Failed to get registration token. Check your GitHub token and repository.${NC}"
        exit 1
    fi
    
    # Configure runner
    ./config.sh \
        --url "https://github.com/$GITHUB_REPOSITORY" \
        --token "$REG_TOKEN" \
        --name "$GITHUB_RUNNER_NAME" \
        --labels "$GITHUB_RUNNER_LABELS" \
        --work "_work" \
        --unattended
    
    echo -e "${GREEN}✅ Runner configured successfully${NC}"
}

case "${1:-install}" in
    "install")
        download_and_install_runner
        ;;
    "configure")
        configure_runner
        ;;
    "reconfigure")
        cd "$RUNNER_HOME"
        if [ -f ".runner" ]; then
            ./config.sh remove --token "$GITHUB_TOKEN"
        fi
        configure_runner
        ;;
    *)
        echo "Usage: $0 [install|configure|reconfigure]"
        echo "  install    - Download and install the runner"
        echo "  configure  - Configure the runner with GitHub"
        echo "  reconfigure - Remove and reconfigure the runner"
        exit 1
        ;;
esac