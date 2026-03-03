#!/bin/bash

# GitHub Actions Runner Status Check Script

set -e

# Load environment variables
if [ -f "$(dirname "$0")/../.env" ]; then
    source "$(dirname "$0")/../.env"
fi

RUNNER_HOME="/opt/github-runner"
LOG_DIR="${LOG_DIR:-/opt/github-runner/logs}"
LOCK_FILE_PATH="${LOCK_FILE_DIR}/${LOCK_FILE_NAME:-raspi-build.lock}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        GitHub Actions Runner Status        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
    echo
}

check_runner_status() {
    echo -e "${BLUE}🏃‍♂️ Runner Status:${NC}"
    
    # Check if runner binary exists
    if [ -f "$RUNNER_HOME/bin/Runner.Worker" ]; then
        echo -e "  ✅ Runner binary: ${GREEN}Found${NC}"
    else
        echo -e "  ❌ Runner binary: ${RED}Missing${NC}"
        return 1
    fi
    
    # Check if runner is configured
    if [ -f "$RUNNER_HOME/.runner" ]; then
        echo -e "  ✅ Configuration: ${GREEN}Found${NC}"
        local runner_name=$(jq -r '.agentName' "$RUNNER_HOME/.runner" 2>/dev/null || echo "Unknown")
        echo -e "     Runner name: $runner_name"
    else
        echo -e "  ❌ Configuration: ${RED}Missing${NC}"
        return 1
    fi
    
    # Check if runner is running
    if pgrep -f "./bin/Runner.Worker" > /dev/null; then
        local runner_pid=$(pgrep -f "./bin/Runner.Worker")
        echo -e "  ✅ Process: ${GREEN}Running${NC} (PID: $runner_pid)"
        
        # Check how long it's been running
        local start_time=$(stat -c %Y /proc/$runner_pid 2>/dev/null || echo "0")
        local current_time=$(date +%s)
        local runtime=$((current_time - start_time))
        local runtime_human=$(date -d@$runtime -u +%H:%M:%S 2>/dev/null || echo "unknown")
        echo -e "     Uptime: $runtime_human"
    else
        echo -e "  ❌ Process: ${RED}Not running${NC}"
    fi
    
    echo
}

check_build_status() {
    echo -e "${BLUE}🔨 Build Status:${NC}"
    
    if [ -f "$LOCK_FILE_PATH" ]; then
        local lock_pid=$(cat "$LOCK_FILE_PATH" 2>/dev/null || echo "")
        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            echo -e "  🟡 Build: ${YELLOW}In progress${NC} (PID: $lock_pid)"
            
            # Try to get process command
            local cmd=$(ps -p "$lock_pid" -o comm= 2>/dev/null || echo "unknown")
            echo -e "     Process: $cmd"
            
            # Check how long the build has been running
            local start_time=$(stat -c %Y "$LOCK_FILE_PATH" 2>/dev/null || echo "0")
            local current_time=$(date +%s)
            local build_time=$((current_time - start_time))
            local build_human=$(date -d@$build_time -u +%H:%M:%S 2>/dev/null || echo "unknown")
            echo -e "     Duration: $build_human"
        else
            echo -e "  🟡 Build: ${YELLOW}Lock file exists but process not running${NC}"
            echo -e "     Lock file: $LOCK_FILE_PATH"
        fi
    else
        echo -e "  ✅ Build: ${GREEN}Idle${NC}"
    fi
    
    echo
}

check_system_resources() {
    echo -e "${BLUE}💻 System Resources:${NC}"
    
    # Disk space
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$disk_usage" -lt 80 ]; then
        echo -e "  ✅ Disk: ${GREEN}$disk_usage% used${NC}"
    elif [ "$disk_usage" -lt 90 ]; then
        echo -e "  🟡 Disk: ${YELLOW}$disk_usage% used${NC}"
    else
        echo -e "  ❌ Disk: ${RED}$disk_usage% used${NC}"
    fi
    
    # Memory
    local mem_info=$(free | awk 'NR==2{printf "%.1f", $3*100/$2 }')
    local mem_usage=${mem_info%.*}
    if [ "$mem_usage" -lt 80 ]; then
        echo -e "  ✅ Memory: ${GREEN}${mem_usage}% used${NC}"
    elif [ "$mem_usage" -lt 90 ]; then
        echo -e "  🟡 Memory: ${YELLOW}${mem_usage}% used${NC}"
    else
        echo -e "  ❌ Memory: ${RED}${mem_usage}% used${NC}"
    fi
    
    # Docker
    if command -v docker &> /dev/null; then
        if docker ps &> /dev/null; then
            local container_count=$(docker ps -q | wc -l)
            echo -e "  ✅ Docker: ${GREEN}Running${NC} ($container_count containers)"
        else
            echo -e "  ❌ Docker: ${RED}Not accessible${NC}"
        fi
    else
        echo -e "  ❌ Docker: ${RED}Not installed${NC}"
    fi
    
    echo
}

check_recent_activity() {
    echo -e "${BLUE}📊 Recent Activity:${NC}"
    
    # Check recent builds from logs
    if [ -f "$LOG_DIR/build.log" ]; then
        local recent_builds=$(grep -c "Starting Docker build" "$LOG_DIR/build.log" 2>/dev/null || echo "0")
        echo -e "  Total builds logged: $recent_builds"
        
        local last_build=$(grep "Starting Docker build" "$LOG_DIR/build.log" | tail -1 | cut -d' ' -f1-2 2>/dev/null || echo "Never")
        echo -e "  Last build: $last_build"
        
        local failed_builds=$(grep -c "Build failed" "$LOG_DIR/build.log" 2>/dev/null || echo "0")
        echo -e "  Failed builds: $failed_builds"
    else
        echo -e "  No build log found"
    fi
    
    # Check service status
    if command -v systemctl &> /dev/null; then
        if systemctl is-active github-actions-runner &> /dev/null; then
            echo -e "  ✅ Service: ${GREEN}Active${NC}"
        else
            echo -e "  ❌ Service: ${RED}Inactive${NC}"
        fi
        
        if systemctl is-enabled github-actions-runner &> /dev/null; then
            echo -e "  ✅ Auto-start: ${GREEN}Enabled${NC}"
        else
            echo -e "  🟡 Auto-start: ${YELLOW}Disabled${NC}"
        fi
    fi
    
    echo
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --json       Output in JSON format"
    echo "  --quiet      Only show errors"
    echo "  --help, -h   Show this help message"
    echo ""
}

# Parse command line arguments
OUTPUT_FORMAT="human"
QUIET_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --json)
            OUTPUT_FORMAT="json"
            shift
            ;;
        --quiet)
            QUIET_MODE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
if [ "$OUTPUT_FORMAT" = "json" ]; then
    # JSON output for programmatic use
    runner_running=$(pgrep -f "./bin/Runner.Worker" > /dev/null && echo "true" || echo "false")
    build_active=$([ -f "$LOCK_FILE_PATH" ] && echo "true" || echo "false")
    disk_usage=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    mem_usage=$(free | awk 'NR==2{printf "%.1f", $3*100/$2 }')
    
    cat << EOF
{
  "runner": {
    "configured": $([ -f "$RUNNER_HOME/.runner" ] && echo "true" || echo "false"),
    "running": $runner_running,
    "name": "$(jq -r '.agentName' "$RUNNER_HOME/.runner" 2>/dev/null || echo "unknown")"
  },
  "build": {
    "active": $build_active,
    "lock_file": "$LOCK_FILE_PATH"
  },
  "system": {
    "disk_usage_percent": $disk_usage,
    "memory_usage_percent": ${mem_usage%.*},
    "docker_available": $(command -v docker &> /dev/null && echo "true" || echo "false")
  },
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
else
    # Human-readable output
    if [ "$QUIET_MODE" = false ]; then
        print_header
    fi
    
    check_runner_status
    check_build_status
    check_system_resources
    
    if [ "$QUIET_MODE" = false ]; then
        check_recent_activity
    fi
fi