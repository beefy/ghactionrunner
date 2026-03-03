#!/bin/bash

# Stop GitHub Actions Runner Script

set -e

# Load environment variables
if [ -f "$(dirname "$0")/../.env" ]; then
    source "$(dirname "$0")/../.env"
fi

RUNNER_HOME="/opt/github-runner"
LOG_DIR="${LOG_DIR:-/opt/github-runner/logs}"
LOCK_FILE_PATH="${LOCK_FILE_DIR}/${LOCK_FILE_NAME}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging function
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} $1" | tee -a "${LOG_DIR}/runner.log"
}

cd "$RUNNER_HOME"

log "${YELLOW}🛑 Stopping GitHub Actions Runner...${NC}"

# Check if build is in progress
if [ -f "$LOCK_FILE_PATH" ]; then
    local lock_pid=$(cat "$LOCK_FILE_PATH" 2>/dev/null || echo "")
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
        log "${RED}⚠️  Build in progress (PID: $lock_pid). Waiting for completion...${NC}"
        while [ -f "$LOCK_FILE_PATH" ] && kill -0 "$lock_pid" 2>/dev/null; do
            log "${YELLOW}Waiting for build to complete...${NC}"
            sleep 10
        done
        log "${GREEN}Build completed, proceeding with shutdown${NC}"
    fi
fi

# Stop runner processes
if pgrep -f "./bin/Runner.Worker" > /dev/null; then
    pkill -f "./bin/Runner.Worker"
    log "${GREEN}Stopped Runner.Worker process${NC}"
fi

if pgrep -f "./run.sh" > /dev/null; then
    pkill -f "./run.sh"
    log "${GREEN}Stopped run.sh process${NC}"
fi

# Remove PID file if it exists
PID_FILE="${LOG_DIR}/runner.pid"
if [ -f "$PID_FILE" ]; then
    rm -f "$PID_FILE"
    log "${GREEN}Removed PID file${NC}"
fi

# Clean up any remaining lock files
if [ -f "$LOCK_FILE_PATH" ]; then
    rm -f "$LOCK_FILE_PATH"
    log "${GREEN}Cleaned up lock file${NC}"
fi

log "${GREEN}✅ GitHub Actions Runner stopped${NC}"