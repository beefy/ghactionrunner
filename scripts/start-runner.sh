#!/bin/bash

# Start GitHub Actions Runner Script

set -e

# Load environment variables
if [ -f "$(dirname "$0")/../.env" ]; then
    source "$(dirname "$0")/../.env"
fi

RUNNER_HOME="/opt/github-runner"
LOG_DIR="${LOG_DIR:-/opt/github-runner/logs}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Create log directory
mkdir -p "$LOG_DIR"

# Logging function
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} $1" | tee -a "${LOG_DIR}/runner.log"
}

cd "$RUNNER_HOME"

# Check if runner is configured
if [ ! -f ".runner" ]; then
    log "${RED}Runner is not configured. Please run setup-runner.sh configure first.${NC}"
    exit 1
fi

# Check if already running
if pgrep -f "./bin/Runner.Worker" > /dev/null; then
    log "${YELLOW}Runner is already running${NC}"
    exit 0
fi

log "${GREEN}🚀 Starting GitHub Actions Runner...${NC}"

# Start the runner
nohup ./run.sh > "${LOG_DIR}/runner-output.log" 2>&1 &
RUNNER_PID=$!

# Save PID
echo $RUNNER_PID > "${LOG_DIR}/runner.pid"

log "${GREEN}✅ Runner started with PID: $RUNNER_PID${NC}"
log "Logs available at: ${LOG_DIR}/runner-output.log"