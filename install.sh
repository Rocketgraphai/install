#!/bin/sh
# install.sh

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default ports
DEFAULT_PORT=80
# DEFAULT_SSL_PORT=443
DEFAULT_XGT_PORT=4367

# Minimum required Docker Compose version
MIN_COMPOSE_VERSION="1.29.0"

# Log functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if script is run with sudo/root (skip this check on macOS)
if [ "$(uname)" != "Darwin" ] && [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root or with sudo"
    exit 1
fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if a port is in use
port_in_use() {
    lsof -iTCP:"$1" -P -n | grep LISTEN >/dev/null 2>&1
}

# Function to compare versions
version_ge() {
    [ "$(printf '%s\n' "$@" | sort -V | head -n 1)" = "$1" ]
}

# Function to run command with timeout
run_with_timeout() {
    local timeout=$1
    shift
    local command="$@"

    # Start the command in background and redirect output
    ($command >/dev/null 2>&1) & local pid=$!

    # Wait for specified timeout
    local count=0
    while [ $count -lt $timeout ] && kill -0 $pid 2>/dev/null; do
        sleep 1
        count=$((count + 1))
    done

    # If process is still running, kill it and return error
    if kill -0 $pid 2>/dev/null; then
        kill -TERM $pid
        wait $pid 2>/dev/null
        return 1
    fi

    # Wait for process to finish and get return code
    wait $pid
    return $?
}

# Read port values from .env file if it exists
read_env_ports() {
    if [ -f .env ]; then
        log_info "Reading port values from .env file..."
        # export $(grep -E '^(MC_PORT|MC_SSL_PORT|MC_DEFAULT_XGT_PORT)=' .env | xargs)
        export $(grep -E '^(MC_PORT|MC_DEFAULT_XGT_PORT)=' .env | xargs)

    fi
}

# Check system requirements
check_requirements() {
    log_info "Checking system requirements..."

    # Check Docker
    if ! command_exists docker; then
        log_error "Docker is not installed. Please install Docker first."
        log_info "Visit https://docs.docker.com/get-docker/ for installation instructions"
        exit 1
    fi

    # Check if Docker is running with a timeout
    if ! run_with_timeout 10 "docker version"; then
        log_error "Docker is not running or not responding. Please start Docker first."
        exit 1
    fi

    # Check Docker Compose
    if ! command_exists docker compose && ! command_exists docker-compose; then
        log_error "Docker Compose is not installed. Please install Docker Compose first."
        log_info "Visit https://docs.docker.com/compose/install/ for installation instructions"
        exit 1
    fi

    # Check Docker Compose version
    compose_version=$(docker compose version --short 2>/dev/null || docker-compose --version | awk '{print $3}')
    compose_version=$(echo "$compose_version" | sed 's/[^0-9.]*//g')
    if ! version_ge "$MIN_COMPOSE_VERSION" "$compose_version"; then
        log_error "Docker Compose version $compose_version is too old. Please install Docker Compose version $MIN_COMPOSE_VERSION or higher."
        exit 1
    fi

    # Check curl
    if ! command_exists curl; then
        log_error "curl is not installed. Please install curl first."
        exit 1
    fi

    # Check for sufficient disk space (at least 1GB free)
    if [ "$(df -P . | awk 'NR==2 {print $4}')" -lt 1048576 ]; then
        log_error "Insufficient disk space. Please ensure at least 1GB of free space."
        exit 1
    fi

    # Check network connectivity
    if ! curl -s --head --request GET https://install.rocketgraph.ai | grep "200" >/dev/null; then
        log_error "Network connectivity issue. Unable to reach https://install.rocketgraph.ai"
        exit 1
    fi
}

# Check for port conflicts
check_ports() {
    log_info "Checking for port conflicts..."

    # "${MC_SSL_PORT:-$DEFAULT_SSL_PORT}"
    ports_to_check="${MC_PORT:-$DEFAULT_PORT} ${MC_DEFAULT_XGT_PORT:-$DEFAULT_XGT_PORT}"

    # Convert space-separated string into individual arguments
    set -- $ports_to_check

    for port in "$@"; do
      if port_in_use "$port"; then
        log_warn "Port $port is already in use. Please stop the existing service or specify a different port."
        exit 1
      fi
    done
}

# Create installation directory (use current directory)
setup_installation_dir() {
    local install_dir="$(pwd)"
    log_info "Using installation directory at ${install_dir}..."

    if [ ! -d "${install_dir}" ]; then
        log_error "Failed to access installation directory"
        exit 1
    fi

    cd "${install_dir}" || exit 1
}

# Download configuration files
download_config() {
    local download_url="https://install.rocketgraph.ai"

    log_info "Downloading configuration files from ${download_url}..."

    # Download docker-compose.yml
    if ! curl -sSL "${download_url}/docker-compose.yml" -o docker-compose.yml; then
        log_error "Failed to download docker-compose.yml"
        exit 1
    fi

    # Download env.template if it exists
    if ! curl -sSL "${download_url}/env.template" -o env.template; then
        log_warn "Failed to download env.template"
    fi

    # Merge env.template with existing .env if it exists
    if [ -f .env ]; then
        log_info "Merging env.template with existing .env file..."
        while IFS= read -r line; do
            key=$(echo "$line" | cut -d '=' -f 1)
            if ! grep -q "^$key=" .env; then
                echo "$line" >> .env
            fi
        done < env.template
    else
        log_info "Creating .env file from env.template..."
        cp env.template .env
    fi

    # Set appropriate permissions
    chmod 600 .env 2>/dev/null
    chmod 644 docker-compose.yml
}

# Pull and start containers
deploy_containers() {
    log_info "Pulling latest container images..."
    if ! run_with_timeout 300 docker compose pull; then
        log_error "Failed to pull container images"
        exit 1
    fi

    log_info "Starting containers..."
    if ! docker compose up -d; then
        log_error "Failed to start containers"
        exit 1
    fi
}

# Main installation process
main() {
    log_info "Starting installation process..."

    check_requirements
    read_env_ports
    check_ports
    setup_installation_dir
    download_config
    deploy_containers

    log_info "Installation completed successfully!"
    log_info "Your application is now running at http://localhost:${MC_PORT:-$DEFAULT_PORT}"
    log_info "To check the status, run: docker compose ps"
    log_info "To view logs, run: docker compose logs"
}

# Run main function
main
