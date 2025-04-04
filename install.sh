#!/bin/sh
# install.sh

# Color codes for output.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color.

# Default ports.
DEFAULT_PORT=80
DEFAULT_SSL_PORT=443
DEFAULT_XGT_PORT=4367

# Minimum required Docker Compose version.
MIN_COMPOSE_VERSION="1.29.0"

DOWNLOAD_URL="https://github.com/Rocketgraphai/rocketgraph"

# Log functions.
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to check if a command exists.
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if a port is in use.
port_in_use() {
    lsof -iTCP:"$1" -P -n | grep LISTEN >/dev/null 2>&1
}

# Function to compare versions.
version_ge() {
    [ "$(printf '%s\n' "$@" | sort -V | head -n 1)" = "$1" ]
}

# Function to run command with timeout.
run_with_timeout() {
    local timeout=$1
    shift
    local command="$@"

    # Start the command in background and redirect output.
    ($command >/dev/null 2>&1) & local pid=$!

    # Wait for specified timeout.
    local count=0
    while [ $count -lt $timeout ] && kill -0 $pid 2>/dev/null; do
        sleep 1
        count=$((count + 1))
    done

    # If process is still running, kill it and return error.
    if kill -0 $pid 2>/dev/null; then
        kill -TERM $pid
        wait $pid 2>/dev/null
        return 1
    fi

    # Wait for process to finish and get return code.
    wait $pid
    return $?
}

# Check system requirements.
check_requirements_docker() {
    log_info "Checking system requirements."

    # Check if Docker is installed.
    if ! command_exists docker; then
        log_error "Docker is not installed. Please install Docker first."
        log_info "Visit https://docs.docker.com/get-docker/ for installation instructions."
        exit 1
    fi

    # Check that Docker is running and the user has permissions to use it.
    if ! run_with_timeout 10 "docker ps"; then
        log_error "Docker is either not running or this user doesn't have permission to use Docker. Make sure Docker is started. If Docker is running, it is likely the user doesn't have permission to use Docker. Either run the script as root or contact your system administrator."
        exit 1
    fi

    # Check if Docker Compose is installed.
    if ! run_with_timeout 10 "docker compose version"; then
        log_error "Docker is installed but Compose is not. Please install Docker Compose first."
        log_info "Visit https://docs.docker.com/compose/install/ for installation instructions."
        exit 1
    fi

    # Check Docker Compose version.
    compose_version=$(docker compose version --short 2>/dev/null || docker-compose --version | awk '{print $3}')
    compose_version=$(echo "$compose_version" | sed 's/[^0-9.]*//g')
    if ! version_ge "$MIN_COMPOSE_VERSION" "$compose_version"; then
        log_error "Docker Compose version $compose_version is too old. Please install Docker Compose version $MIN_COMPOSE_VERSION or higher."
        exit 1
    fi

    # Check curl.
    if ! command_exists curl; then
        log_error "curl is not installed. Please install curl first."
        exit 1
    fi

    # Check for sufficient disk space (at least 1GB free).
    if [ "$(df -P . | awk 'NR==2 {print $4}')" -lt 1048576 ]; then
        log_error "Insufficient disk space. Please ensure at least 1GB of free space."
        exit 1
    fi

    # Check network connectivity.
    if ! curl -s --head --request GET ${DOWNLOAD_URL} | grep "200" >/dev/null; then
        log_error "Network connectivity issue. Unable to reach ${DOWNLOAD_URL}."
        exit 1
    fi
}

# Check system requirements.
check_requirements_podman() {
    log_info "Checking system requirements."

    # Check if podman is installed.
    if ! command_exists podman; then
        log_error "podman is not installed. Please install podman first."
        exit 1
    fi

    # Check that podman is running and the user has permissions to use it.
    if ! run_with_timeout 10 "podman ps"; then
        log_error "podman is either not running or this user doesn't have permission to use Docker. Make sure podman is started. If podman is running, it is likely the user doesn't have permission to use podman. Either run the script as root or contact your system administrator."
        exit 1
    fi

    # Check if podman compose is installed.
    if ! run_with_timeout 10 "podman-compose version"; then
        log_error "podman is installed but compose is not. Please install podman-compose first."
        exit 1
    fi

    # Check curl.
    if ! command_exists curl; then
        log_error "curl is not installed. Please install curl first."
        exit 1
    fi

    # Check for sufficient disk space (at least 1GB free).
    if [ "$(df -P . | awk 'NR==2 {print $4}')" -lt 1048576 ]; then
        log_error "Insufficient disk space. Please ensure at least 1GB of free space."
        exit 1
    fi

    # Check network connectivity.
    if ! curl -s --head --request GET ${DOWNLOAD_URL} | grep "200" >/dev/null; then
        log_error "Network connectivity issue. Unable to reach ${DOWNLOAD_URL}."
        exit 1
    fi
}

# Create installation directory (use current directory).
check_installation_dir() {
    local install_dir="$(pwd)"
    log_info "Using installation directory at ${install_dir}/."

    if [ ! -w "${install_dir}" ]; then
        log_error "Write permissions required in ${install_dir}".
        exit 1
    fi
}

# Download config files.
download_config() {
    local url="https://raw.githubusercontent.com/Rocketgraphai/rocketgraph/main"

    log_info "Downloading config files from ${DOWNLOAD_URL}/."

    # Download docker-compose.yml.
    if ! curl -sSL "${url}/docker-compose.yml" -o docker-compose.yml; then
        log_error "Failed to download docker-compose.yml."
        exit 1
    fi

    # Download env.template.
    if ! curl -sSL "${url}/env.template" -o env.template; then
        log_warn "Failed to download env.template."
    fi

    # Copy env.template to .env if .env doesn't exist.
    if [ ! -f .env ]; then
        log_info "Creating .env file from env.template."
        cp env.template .env
    fi

    # Set appropriate permissions.
    chmod 600 .env 2>/dev/null
    chmod 644 docker-compose.yml
}

# Set the values of variables needed by the script.  These get a value from the
# .env file or a default value.  Note that these variables do NOT affect the
# docker containers.  They get their values strictly from the .env file.
set_variables() {
    log_info "Reading needed values from .env file."

    MC_PORT="$DEFAULT_PORT"
    if grep -q '^MC_PORT=' .env; then
        MC_PORT=$(grep -E '^MC_PORT=' .env | cut -d'=' -f2-)
    fi

    MC_SSL_PORT="$DEFAULT_SSL_PORT"
    if grep -q '^MC_SSL_PORT=' .env; then
        MC_SSL_PORT=$(grep -E '^MC_SSL_PORT=' .env | cut -d'=' -f2-)
    fi

    MC_DEFAULT_XGT_PORT="$DEFAULT_XGT_PORT"
    if grep -q '^MC_DEFAULT_XGT_PORT=' .env; then
        MC_DEFAULT_XGT_PORT=$(grep -E '^MC_DEFAULT_XGT_PORT=' .env | cut -d'=' -f2-)
    fi

    # Determine if SSL is being used to serve Mission Control.
    USE_SSL=0
    if grep -q '^MC_SSL_PUBLIC_CERT=' .env &&
       grep -q '^MC_SSL_PRIVATE_KEY=' .env; then
        USE_SSL=1
    fi
}

# Check for port conflicts.
check_ports() {
    log_info "Checking for port conflicts."

    ports_to_check="${MC_PORT} ${MC_DEFAULT_XGT_PORT}"
    if [ "$USE_SSL" -eq 1 ]; then
        ports_to_check="${ports_to_check} ${MC_SSL_PORT}"
    fi

    for port in ${ports_to_check}; do
        if port_in_use "$port"; then
            log_warn "Port $port is already in use. Please stop the existing service or specify a different port."
            exit 1
        fi
    done
}

# Pull and start containers.
deploy_containers_docker() {
    log_info "Pulling latest container images."
    if ! output=$(run_with_timeout 300 docker compose pull 2>&1); then
        log_error "Failed to pull container images. Error: $output"
        exit 1
    fi

    log_info "Starting containers."
    if ! output=$(docker compose up -d 2>&1); then
        log_error "Failed to start containers. Error: $output"
        exit 1
    fi
}

# Pull and start containers.
deploy_containers_podman() {
    log_info "Pulling latest container images."
    # Set the MongoDB image for Power architecture
    export MC_MONGODB_IMAGE=ibmcom/mongodb-ppc64le

    # Ensure volume exists
    if ! podman volume inspect rocketgraph_mongodb-data >/dev/null 2>&1; then
        log_info "Creating MongoDB volume..."
        podman volume create rocketgraph_mongodb-data
    fi

    # Fix permissions on the volume for MongoDB
    log_info "Setting correct permissions on MongoDB volume..."
    podman unshare chown -R 999:999 "$(podman volume inspect rocketgraph_mongodb-data -f '{{.Mountpoint}}')"

    # Check if there are existing containers that need to be removed
    if podman ps -a --format "{{.Names}}" | grep -q "rocketgraph_"; then
        log_info "Removing existing Rocketgraph containers..."
        podman-compose down
    fi
    # Start the services
    log_info "Starting Rocketgraph services with Podman..."
    # podman-compose up -d
    podman-compose up -d mongodb
    sleep 3
    podman-compose up -d backend
    sleep 5
    podman-compose up -d xgt
    sleep 3
    podman-compose up -d frontend

    # Allow user to log off and keep containers running
    loginctl enable-linger
    log_info "Rocketgraph startup complete. Check status with: podman-compose ps"
}

# Main installation process.
main() {
    log_info "Starting installation process."

    if [ $(uname -m) == "ppc64le" ]; then
        check_requirements_podman
    else
        check_requirements_docker
    fi
    check_installation_dir
    download_config
    set_variables
    check_ports
    if [ $(uname -m) == "ppc64le" ]; then
        deploy_containers_podman
    else
        deploy_containers_docker
    fi

    log_info "Installation completed successfully!"
    if [ "$USE_SSL" -eq 1 ]; then
      log_info "Mission Control is now running at https://localhost:${MC_SSL_PORT}"
    else
      log_info "Mission Control is now running at http://localhost:${MC_PORT}"
    fi
    if [ $(uname -m) == "ppc64le" ]; then
        log_info "To check the status, run: podman-compose ps"
        log_info "To view logs, run: podman-compose logs"
    else
        log_info "To check the status, run: docker compose ps"
        log_info "To view logs, run: docker compose logs"
    fi
}

# Run main function.
main
