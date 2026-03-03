#!/bin/bash

# Cleanup Script for GitHub Actions Runner

set -e

# Load environment variables
if [ -f "$(dirname "$0")/../.env" ]; then
    source "$(dirname "$0")/../.env"
fi

LOG_DIR="${LOG_DIR:-/opt/github-runner/logs}"
LOCK_FILE_PATH="${LOCK_FILE_DIR}/${LOCK_FILE_NAME}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} $1" | tee -a "${LOG_DIR}/cleanup.log"
}

cleanup_docker() {
    log "${BLUE}🐳 Cleaning up Docker resources...${NC}"
    
    # Remove stopped containers
    stopped_containers=$(docker ps -aq --filter "status=exited")
    if [ -n "$stopped_containers" ]; then
        docker rm $stopped_containers
        log "${GREEN}Removed stopped containers${NC}"
    fi
    
    # Remove dangling images
    dangling_images=$(docker images -qf "dangling=true")
    if [ -n "$dangling_images" ]; then
        docker rmi $dangling_images
        log "${GREEN}Removed dangling images${NC}"
    fi
    
    # Clean up build cache
    docker builder prune -f
    log "${GREEN}Cleaned build cache${NC}"
    
    # Remove volumes not used by any containers
    docker volume prune -f
    log "${GREEN}Removed unused volumes${NC}"
    
    log "${GREEN}✅ Docker cleanup completed${NC}"
}

cleanup_logs() {
    log "${BLUE}📄 Cleaning up old logs...${NC}"
    
    if [ -d "$LOG_DIR" ]; then
        # Keep only last 7 days of logs
        find "$LOG_DIR" -name "*.log" -mtime +7 -delete 2>/dev/null || true
        log "${GREEN}Removed logs older than 7 days${NC}"
        
        # Compress large log files
        find "$LOG_DIR" -name "*.log" -size +100M -exec gzip {} \; 2>/dev/null || true
        log "${GREEN}Compressed large log files${NC}"
    fi
    
    log "${GREEN}✅ Log cleanup completed${NC}"
}

cleanup_workspace() {
    local workspace_dir="/opt/github-runner/_work"
    
    log "${BLUE}🗂️  Cleaning up workspace...${NC}"
    
    if [ -d "$workspace_dir" ]; then
        # Remove temporary files
        find "$workspace_dir" -name "*.tmp" -delete 2>/dev/null || true
        find "$workspace_dir" -name ".DS_Store" -delete 2>/dev/null || true
        
        # Clean up old workflow runs (keep last 5)
        for repo_dir in "$workspace_dir"/*; do
            if [ -d "$repo_dir" ]; then
                ls -t "$repo_dir" | tail -n +6 | xargs -r rm -rf
            fi
        done
        
        log "${GREEN}Cleaned workspace directory${NC}"
    fi
    
    log "${GREEN}✅ Workspace cleanup completed${NC}"
}

cleanup_lock_files() {
    log "${BLUE}🔒 Cleaning up stale lock files...${NC}"
    
    if [ -f "$LOCK_FILE_PATH" ]; then
        local lock_pid=$(cat "$LOCK_FILE_PATH" 2>/dev/null || echo "")
        if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
            rm -f "$LOCK_FILE_PATH"
            log "${GREEN}Removed stale lock file${NC}"
        fi
    fi
    
    log "${GREEN}✅ Lock file cleanup completed${NC}"
}

# Parse command line arguments
CLEANUP_DOCKER=true
CLEANUP_LOGS=true
CLEANUP_WORKSPACE=true
CLEANUP_LOCKS=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-docker)
            CLEANUP_DOCKER=false
            shift
            ;;
        --no-logs)
            CLEANUP_LOGS=false
            shift
            ;;
        --no-workspace)
            CLEANUP_WORKSPACE=false
            shift
            ;;
        --no-locks)
            CLEANUP_LOCKS=false
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --no-docker     Skip Docker cleanup"
            echo "  --no-logs       Skip log cleanup"
            echo "  --no-workspace  Skip workspace cleanup"
            echo "  --no-locks      Skip lock file cleanup"
            echo "  --help, -h      Show this help message"
            exit 0
            ;;
        *)
            log "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

log "${GREEN}🧹 Starting system cleanup...${NC}"

# Perform cleanup operations
if [ "$CLEANUP_LOCKS" = true ]; then
    cleanup_lock_files
fi

if [ "$CLEANUP_DOCKER" = true ]; then
    cleanup_docker
fi

if [ "$CLEANUP_LOGS" = true ]; then
    cleanup_logs
fi

if [ "$CLEANUP_WORKSPACE" = true ]; then
    cleanup_workspace
fi

# System information
log "${BLUE}📊 System information after cleanup:${NC}"
df -h / | tail -1 | awk '{print "Disk usage: " $3 "/" $2 " (" $5 ")"}' | tee -a "${LOG_DIR}/cleanup.log"
free -h | grep '^Mem:' | awk '{print "Memory usage: " $3 "/" $2}' | tee -a "${LOG_DIR}/cleanup.log"

log "${GREEN}✅ System cleanup completed successfully${NC}"