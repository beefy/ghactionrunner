#!/bin/bash

# Docker Build Script with File Locking for Raspberry Pi
# This script creates a lock file during builds to prevent overworking the Pi

set -e

# Load environment variables
if [ -f "$(dirname "$0")/../.env" ]; then
    source "$(dirname "$0")/../.env"
else
    echo "Error: .env file not found"
    exit 1
fi

# Default values
LOCK_FILE_PATH="${LOCK_FILE_DIR}/${LOCK_FILE_NAME}"
BUILD_TIMEOUT=${BUILD_TIMEOUT:-3600}
LOG_DIR=${LOG_DIR:-"/opt/github-runner/logs"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_DIR}/build.log"
}

# Function to check if a build is already running
check_lock() {
    if [ -f "$LOCK_FILE_PATH" ]; then
        local lock_pid=$(cat "$LOCK_FILE_PATH" 2>/dev/null || echo "")
        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            log "ERROR" "${RED}Build already in progress (PID: $lock_pid)${NC}"
            log "ERROR" "Lock file: $LOCK_FILE_PATH"
            echo "GITHUB_OUTPUT=build_status=skipped,error=build_in_progress" >> $GITHUB_OUTPUT 2>/dev/null || true
            exit 1
        else
            log "WARN" "${YELLOW}Stale lock file found, removing...${NC}"
            rm -f "$LOCK_FILE_PATH"
        fi
    fi
}

# Function to create lock file
create_lock() {
    echo $$ > "$LOCK_FILE_PATH"
    log "INFO" "${GREEN}Created build lock file: $LOCK_FILE_PATH (PID: $$)${NC}"
}

# Function to remove lock file
remove_lock() {
    if [ -f "$LOCK_FILE_PATH" ]; then
        rm -f "$LOCK_FILE_PATH"
        log "INFO" "${GREEN}Removed build lock file${NC}"
    fi
}

# Function to handle cleanup on exit
cleanup() {
    local exit_code=$?
    log "INFO" "${BLUE}Cleaning up build environment...${NC}"
    remove_lock
    
    if [ $exit_code -eq 0 ]; then
        log "INFO" "${GREEN}Build completed successfully${NC}"
        echo "GITHUB_OUTPUT=build_status=success" >> $GITHUB_OUTPUT 2>/dev/null || true
    else
        log "ERROR" "${RED}Build failed with exit code: $exit_code${NC}"
        echo "GITHUB_OUTPUT=build_status=failed,exit_code=$exit_code" >> $GITHUB_OUTPUT 2>/dev/null || true
    fi
}

# Function to handle timeout
timeout_handler() {
    log "ERROR" "${RED}Build timeout reached (${BUILD_TIMEOUT}s)${NC}"
    echo "GITHUB_OUTPUT=build_status=timeout" >> $GITHUB_OUTPUT 2>/dev/null || true
    cleanup
    exit 124
}

# Function to build and push Docker image
build_and_push() {
    local dockerfile_path="${1:-Dockerfile}"
    local image_name="$2"
    local image_tag="${3:-latest}"
    local build_context="${4:-.}"
    local build_args="${5:-}"
    
    if [ -z "$image_name" ]; then
        log "ERROR" "${RED}Image name is required${NC}"
        exit 1
    fi
    
    local full_image_name="${DOCKER_REGISTRY}/${DOCKERHUB_USERNAME}/${image_name}:${image_tag}"
    
    log "INFO" "${BLUE}Starting Docker build...${NC}"
    log "INFO" "Dockerfile: $dockerfile_path"
    log "INFO" "Image: $full_image_name"
    log "INFO" "Build context: $build_context"
    log "INFO" "Build args: $build_args"
    
    # Check if Dockerfile exists
    if [ ! -f "$dockerfile_path" ]; then
        log "ERROR" "${RED}Dockerfile not found: $dockerfile_path${NC}"
        exit 1
    fi
    
    # Login to Docker registry
    log "INFO" "${BLUE}Logging into Docker registry...${NC}"
    echo "$DOCKERHUB_TOKEN" | docker login "$DOCKER_REGISTRY" -u "$DOCKERHUB_USERNAME" --password-stdin
    
    # Build the image
    log "INFO" "${BLUE}Building Docker image...${NC}"
    local build_cmd="docker build -f $dockerfile_path -t $full_image_name $build_context"
    
    if [ -n "$build_args" ]; then
        IFS=',' read -ra ARGS <<< "$build_args"
        for arg in "${ARGS[@]}"; do
            build_cmd="$build_cmd --build-arg $arg"
        done
    fi
    
    log "INFO" "Build command: $build_cmd"
    eval "$build_cmd"
    
    # Push the image
    log "INFO" "${BLUE}Pushing Docker image...${NC}"
    docker push "$full_image_name"
    
    # Tag as latest if not already latest
    if [ "$image_tag" != "latest" ]; then
        local latest_image="${DOCKER_REGISTRY}/${DOCKERHUB_USERNAME}/${image_name}:latest"
        docker tag "$full_image_name" "$latest_image"
        docker push "$latest_image"
        log "INFO" "${GREEN}Also pushed as: $latest_image${NC}"
    fi
    
    # Cleanup local images to save space
    log "INFO" "${BLUE}Cleaning up local images...${NC}"
    docker rmi "$full_image_name" 2>/dev/null || true
    if [ "$image_tag" != "latest" ]; then
        docker rmi "${DOCKER_REGISTRY}/${DOCKERHUB_USERNAME}/${image_name}:latest" 2>/dev/null || true
    fi
    
    # Clean up dangling images
    docker image prune -f
    
    log "INFO" "${GREEN}Docker build and push completed successfully${NC}"
}

# Set up signal handlers
trap cleanup EXIT
trap timeout_handler ALARM

# Create log directory
mkdir -p "$LOG_DIR"

# Parse command line arguments
DOCKERFILE_PATH="${1:-Dockerfile}"
IMAGE_NAME="$2"
IMAGE_TAG="${3:-latest}"
BUILD_CONTEXT="${4:-.}"
BUILD_ARGS="$5"

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [dockerfile_path] <image_name> [image_tag] [build_context] [build_args]"
    echo ""
    echo "Arguments:"
    echo "  dockerfile_path  Path to Dockerfile (default: Dockerfile)"
    echo "  image_name       Name of the Docker image (required)"
    echo "  image_tag        Tag for the image (default: latest)"
    echo "  build_context    Build context path (default: .)"
    echo "  build_args       Comma-separated build arguments (optional)"
    echo ""
    echo "Environment variables:"
    echo "  DOCKERHUB_USERNAME     Docker Hub username"
    echo "  DOCKERHUB_TOKEN        Docker Hub access token"
    echo "  DOCKER_REGISTRY        Docker registry URL (default: docker.io)"
    echo "  LOCK_FILE_DIR          Directory for lock file (default: /tmp)"
    echo "  LOCK_FILE_NAME         Name of lock file (default: raspi-build.lock)"
    echo "  BUILD_TIMEOUT          Build timeout in seconds (default: 3600)"
    exit 0
fi

# Main execution
log "INFO" "${GREEN}🚀 Starting Raspberry Pi Docker build process${NC}"

# Check for existing builds
check_lock

# Create lock file
create_lock

# Set timeout
(sleep "$BUILD_TIMEOUT" && kill -ALRM $$ 2>/dev/null) &
timeout_pid=$!

# Perform the build
build_and_push "$DOCKERFILE_PATH" "$IMAGE_NAME" "$IMAGE_TAG" "$BUILD_CONTEXT" "$BUILD_ARGS"

# Cancel timeout
kill $timeout_pid 2>/dev/null || true

log "INFO" "${GREEN}✅ Build process completed successfully${NC}"