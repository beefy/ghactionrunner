# GitHub Actions Self-Hosted Runner for Raspberry Pi

A comprehensive solution for running GitHub Actions on a Raspberry Pi with Docker image building capabilities and resource management through file-based locking.

## Features

- 🏃‍♂️ **Self-hosted GitHub Actions runner** optimized for Raspberry Pi
- 🐳 **Docker image building and pushing** to DockerHub
- 🔒 **File-based locking mechanism** to prevent resource overload
- 📊 **Resource monitoring and cleanup** 
- 🔄 **Automatic service management** with systemd
- 📝 **Comprehensive logging** and monitoring
- 🛡️ **Security hardening** and sandboxing options
- 🗂️ **Organized project structure** with modular scripts

## Quick Start

### Prerequisites

- Raspberry Pi (3B+ or newer recommended)
- Raspberry Pi OS (64-bit recommended)
- Docker and Docker Compose
- GitHub Personal Access Token
- DockerHub account and access token

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/yourusername/ghactionrunner.git
   cd ghactionrunner
   ```

2. **Run the installation script:**
   ```bash
   sudo chmod +x install.sh
   sudo ./install.sh
   ```

3. **Configure environment variables:**
   ```bash
   sudo -u github-runner cp /opt/github-runner/.env.template /opt/github-runner/.env
   sudo -u github-runner nano /opt/github-runner/.env
   ```

4. **Configure the runner:**
   ```bash
   sudo -u github-runner /opt/github-runner/scripts/setup-runner.sh configure
   ```

5. **Start the service:**
   ```bash
   sudo systemctl enable github-actions-runner
   sudo systemctl start github-actions-runner
   ```

## Configuration

### Environment Variables

Copy `.env.template` to `.env` and configure the following:

| Variable | Description | Required |
|----------|-------------|----------|
| `GITHUB_TOKEN` | GitHub Personal Access Token | Yes |
| `GITHUB_REPOSITORY` | Repository in format `owner/repo` | Yes |
| `GITHUB_RUNNER_NAME` | Name for your runner | Yes |
| `GITHUB_RUNNER_LABELS` | Comma-separated labels | Yes |
| `DOCKERHUB_USERNAME` | DockerHub username | Yes |
| `DOCKERHUB_TOKEN` | DockerHub access token | Yes |
| `LOCK_FILE_DIR` | Directory for lock files | No |
| `LOCK_FILE_NAME` | Lock file name | No |
| `BUILD_TIMEOUT` | Build timeout in seconds | No |

### GitHub Personal Access Token

Create a token with these scopes:
- `repo` (for private repositories)
- `admin:repo_hook` (for webhooks)
- `read:org` (if using organization repositories)

## Usage

### File Locking Mechanism

The runner uses a file-based locking system to prevent resource conflicts:

- **Lock file created:** When a build starts (`/tmp/raspi-build.lock` by default)
- **Lock file deleted:** When build completes or fails
- **Concurrent builds:** Prevented by checking for existing lock files

### Using in GitHub Workflows

Add this to your repository's `.github/workflows/build.yml`:

```yaml
name: Build on Raspberry Pi

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: [self-hosted, linux, arm64, docker, raspi]
    steps:
      - uses: actions/checkout@v4
      
      - name: Build and push Docker image
        env:
          DOCKERHUB_USERNAME: ${{ secrets.DOCKERHUB_USERNAME }}
          DOCKERHUB_TOKEN: ${{ secrets.DOCKERHUB_TOKEN }}
        run: |
          /opt/github-runner/scripts/docker-build.sh \
            Dockerfile \
            my-app \
            latest \
            . \
            "BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
```

### Docker Build Script

The `docker-build.sh` script provides:

- **Automatic locking** prevents concurrent builds
- **DockerHub authentication** and image pushing
- **Build timeout handling** with configurable limits
- **Comprehensive logging** with timestamps
- **Cleanup operations** to free disk space
- **Error handling** with proper exit codes

#### Usage Examples

```bash
# Basic build and push
./scripts/docker-build.sh Dockerfile my-app latest

# With custom build context
./scripts/docker-build.sh docker/Dockerfile.prod my-app v1.0.0 ./src

# With build arguments
./scripts/docker-build.sh Dockerfile my-app latest . "NODE_ENV=production,API_URL=https://api.example.com"
```

## Service Management

### Systemd Service

The runner is managed as a systemd service:

```bash
# Check status
sudo systemctl status github-actions-runner

# Start service
sudo systemctl start github-actions-runner

# Stop service (waits for builds to complete)
sudo systemctl stop github-actions-runner

# Restart service
sudo systemctl restart github-actions-runner

# View logs
sudo journalctl -u github-actions-runner -f
```

### Manual Management

```bash
# Start runner manually
sudo -u github-runner /opt/github-runner/scripts/start-runner.sh

# Stop runner manually
sudo -u github-runner /opt/github-runner/scripts/stop-runner.sh

# Clean up resources
sudo -u github-runner /opt/github-runner/scripts/cleanup.sh
```

## Monitoring and Logs

### Log Files

- **Runner logs:** `/opt/github-runner/logs/runner.log`
- **Build logs:** `/opt/github-runner/logs/build.log`
- **Service logs:** `/opt/github-runner/logs/service.log`
- **Cleanup logs:** `/opt/github-runner/logs/cleanup.log`

### Monitoring Commands

```bash
# Check system resources
df -h
free -h
docker system df

# Monitor active builds
ls -la /tmp/raspi-build.lock

# View recent build activity
tail -f /opt/github-runner/logs/build.log

# Check Docker containers
docker ps -a
```

## Docker Compose Deployment (Alternative)

For containerized deployment:

```bash
# Build and start with docker-compose
docker-compose up -d

# Stop services
docker-compose down

# View logs
docker-compose logs -f github-runner

# Enable monitoring (Watchtower)
docker-compose --profile monitoring up -d

# Enable registry cache
docker-compose --profile cache up -d
```

## Maintenance

### Regular Cleanup

The `cleanup.sh` script handles:
- Docker container and image cleanup
- Log rotation and compression
- Workspace directory management
- Stale lock file removal

```bash
# Run full cleanup
./scripts/cleanup.sh

# Selective cleanup
./scripts/cleanup.sh --no-docker --no-logs
```

### Updates

```bash
# Update runner binary
sudo -u github-runner /opt/github-runner/scripts/setup-runner.sh install

# Reconfigure runner
sudo -u github-runner /opt/github-runner/scripts/setup-runner.sh reconfigure
```

## Security Considerations

### Security Features

- **Dedicated user account** with minimal privileges
- **Docker socket access** controlled through group membership
- **File system restrictions** via systemd security settings
- **Resource limits** to prevent resource exhaustion
- **Network isolation** options in Docker Compose setup

### Best Practices

1. **Regular updates** of the runner binary and system packages
2. **Token rotation** for GitHub and DockerHub access
3. **Log monitoring** for suspicious activity
4. **Resource monitoring** to prevent overload
5. **Backup** of runner configuration and logs

## Troubleshooting

### Common Issues

#### Runner not starting
```bash
# Check service status
sudo systemctl status github-actions-runner

# Check configuration
sudo -u github-runner ls -la /opt/github-runner/.runner

# Reconfigure if needed
sudo -u github-runner /opt/github-runner/scripts/setup-runner.sh reconfigure
```

#### Build failures
```bash
# Check lock file status
ls -la /tmp/raspi-build.lock

# Check Docker service
sudo systemctl status docker

# Check available disk space
df -h

# Manual cleanup
sudo -u github-runner /opt/github-runner/scripts/cleanup.sh
```

#### Permission issues
```bash
# Fix ownership
sudo chown -R github-runner:github-runner /opt/github-runner

# Check Docker group membership
groups github-runner

# Add to Docker group if missing
sudo usermod -aG docker github-runner
```

### Log Analysis

```bash
# View recent errors
sudo journalctl -u github-actions-runner --since "1 hour ago" -p err

# Check build failures
grep -i error /opt/github-runner/logs/build.log

# Monitor resource usage during builds
tail -f /opt/github-runner/logs/build.log | grep -E "(CPU|Memory|Disk)"
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- GitHub Actions team for the self-hosted runner
- Docker team for containerization platform
- Raspberry Pi Foundation for the affordable hardware platform
process to build images and deploy to dockerhub
