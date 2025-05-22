#!/bin/sh
# install.sh

# Color codes for output.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color.

# Default ports.
DEFAULT_HTTP_PORT=80
DEFAULT_HTTPS_PORT=443
DEFAULT_DOCKER_CMD=docker
DEFAULT_USE_TIMEOUT=1

# Initialize variables with default values
HTTP_PORT=$DEFAULT_HTTP_PORT
HTTPS_PORT=$DEFAULT_HTTPS_PORT
DOCKER_CMD=$DEFAULT_DOCKER_CMD
USE_TIMEOUT=$DEFAULT_USE_TIMEOUT

# Parse command line options
while [ $# -gt 0 ]; do
  case "$1" in
    --http-port)
      if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
        HTTP_PORT=$2
        shift 2
      else
        log_error "Error: Argument for $1 is missing"
        exit 1
      fi
      ;;
    --https-port)
      if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
        HTTPS_PORT=$2
        shift 2
      else
        log_error "Error: Argument for $1 is missing"
        exit 1
      fi
      ;;
    --docker-command)
      if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
        DOCKER_CMD=$2
        shift 2
      else
        log_error "Error: Argument for $1 is missing"
        exit 1
      fi
      ;;
    --use-timeout)
      if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
        USE_TIMEOUT=$2
        shift 2
      else
        log_error "Error: Argument for $1 is missing"
        exit 1
      fi
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo "Available options:"
      echo "  --http-port PORT   Specify custom HTTP port (default: $DEFAULT_HTTP_PORT)"
      echo "  --https-port PORT  Specify custom HTTPS port (default: $DEFAULT_HTTPS_PORT)"
      echo "  --docker-command DOCKER_COMMAND  Specify explicit location of the docker command (default: $DEFAULT_DOCKER_CMD)"
      echo "  --use-time (0 or 1)  Run docker asynchronously with a timeout (default: $DEFAULT_DOCKER_CMD)"
      echo "  -h, --help         Show this help message"
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      echo "Use -h or --help to see available options"
      exit 1
      ;;
  esac
done

# Minimum required Docker Compose version.
MIN_COMPOSE_VERSION="1.29.0"

DOWNLOAD_URL="https://github.com/Rocketgraphai/rocketgraph"

# Log functions.
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

portable_sed_i() {
  # Usage: portable_sed_i 's|pattern|replacement|' filename
  local expr="$1"
  local file="$2"

  if sed --version >/dev/null 2>&1; then
    # GNU sed
    sed -i "$expr" "$file"
  else
    # BSD sed (macOS)
    sed -i '' "$expr" "$file"
  fi
}

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
    if ! command_exists $DOCKER_CMD; then
        log_error "Docker is not installed. Please install Docker first."
        log_info "Visit https://docs.docker.com/get-docker/ for installation instructions."
        exit 1
    fi

    # Check that Docker is running and the user has permissions to use it.
    if ! run_with_timeout 10 "$DOCKER_CMD ps"; then
        log_error "Docker is either not running or this user doesn't have permission to use Docker. Make sure Docker is started. If Docker is running, it is likely the user doesn't have permission to use Docker. Either run the script as root or contact your system administrator."
        exit 1
    fi

    # Check if Docker Compose is installed.
    if ! run_with_timeout 10 "$DOCKER_CMD compose version"; then
        log_error "Docker is installed but Compose is not. Please install Docker Compose first."
        log_info "Visit https://docs.docker.com/compose/install/ for installation instructions."
        exit 1
    fi

    # Check Docker Compose version.
    compose_version=$($DOCKER_CMD compose version --short 2>/dev/null || docker-compose --version | awk '{print $3}')
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
        log_error "podman is either not running or this user doesn't have permission to use podman. Make sure podman is started. If podman is running, it is likely the user doesn't have permission to use podman. Either run the script as root or contact your system administrator."
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

    # Check if .env file already exists
    if [ -f .env ]; then
        log_error "A .env file already exists. Installation aborted."
        log_error "Please remove or rename the .env file or go to a different directory if you want to reinstall."
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
    if ! curl -sSL "${url}/env.template" -o .env; then
        log_warn "Failed to download a .env file."
        exit 1
    fi

    # Set appropriate permissions.
    chmod 600 .env 2>/dev/null
    chmod 644 docker-compose.yml
}

# Set the values of variables needed by the script.  These get a value from the
# .env file or a default value.  Note that these variables do NOT affect the
# docker containers.  They get their values strictly from the .env file.
set_variables() {
    log_info "Setting up .env configuration file."

    if grep -q '^#MC_PORT=' .env && [ "$HTTP_PORT" != "$DEFAULT_HTTP_PORT" ]; then
        log_info "Using non-standard HTTP_PORT=${HTTP_PORT}"
        portable_sed_i "s|^#MC_PORT=${DEFAULT_HTTP_PORT}|MC_PORT=${HTTP_PORT}|" .env
    fi

    if grep -q '^#MC_SSL_PORT=' .env && [ "$HTTPS_PORT" != "$DEFAULT_HTTPS_PORT" ]; then
        log_info "Using non-standard HTTPS_PORT=${HTTPS_PORT}"
        portable_sed_i "s|^#MC_SSL_PORT=${DEFAULT_HTTPS_PORT}|MC_SSL_PORT=${HTTPS_PORT}|" .env
    fi

    # Determine if SSL is being used to serve Mission Control.
    USE_SSL=0
    if grep -q '^MC_SSL_PUBLIC_CERT=' .env &&
       grep -q '^MC_SSL_PRIVATE_KEY=' .env; then
        USE_SSL=1
    fi

    # Check if xgt.lic license file exists
    if [ -f xgt.lic ]; then
        log_info "Custom license file found."
        portable_sed_i "s|^#XGT_LICENSE_FILE=/path/to/license/xgt-license.lic|XGT_LICENSE_FILE=$(pwd)/xgt.lic|" .env
    fi
}

# Check for port conflicts.
check_ports() {
    log_info "Checking for port conflicts."

    ports_to_check="${HTTP_PORT}"
    if [ "$USE_SSL" -eq 1 ]; then
        ports_to_check="${ports_to_check} ${HTTPS_PORT}"
    fi

    for port in ${ports_to_check}; do
        if port_in_use "$port"; then
            log_warn "Port $port is already in use. Please stop the existing service or specify a different port."
            log_warn "To specify a different port, see the --http-port, --https-port, and --xgt-port options in the Installation help."
            exit 1
        fi
    done
}

# Pull and start containers.
deploy_containers_docker() {
    local use_timeout=$1

    log_info "Pulling latest container images."
    if [ $use_timeout -eq 1 ] && ! output=$(run_with_timeout 300 $DOCKER_CMD compose pull 2>&1); then
        log_error "Failed to pull container images. Error: $output"
        exit 1
    else
        $DOCKER_CMD compose pull
    fi

    log_info "Starting containers."
    if ! output=$($DOCKER_CMD compose up -d 2>&1); then
        log_error "Failed to start containers. Error: $output"
        exit 1
    fi
}

# Pull and start containers.
deploy_containers_podman() {
    # Set the MongoDB image for Power architecture
    export MC_MONGODB_IMAGE=ibmcom/mongodb-ppc64le
    portable_sed_i 's|^#MC_MONGODB_IMAGE=mongo:latest|MC_MONGODB_IMAGE=ibmcom/mongodb-ppc64le|' .env

    log_info "Pulling latest container images."
    if ! output=$(run_with_timeout 300 podman-compose pull 2>&1); then
        log_error "Failed to pull container images. Error: $output"
        exit 1
    fi

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
        podman-compose down >/dev/null 2>&1
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

    if [ $(uname -m) = "ppc64le" ]; then
        check_requirements_podman
    else
        check_requirements_docker
    fi
    check_installation_dir
    download_config
    set_variables
    check_ports
    if [ $(uname -m) = "ppc64le" ]; then
        deploy_containers_podman
    else
        deploy_containers_docker $USE_TIMEOUT
    fi

    log_info "Installation completed successfully!"
    if [ "$USE_SSL" -eq 1 ]; then
      log_info "Mission Control is now running at https://localhost:${HTTPS_PORT}"
    else
      log_info "Mission Control is now running at http://localhost:${HTTP_PORT}"
    fi
    if [ $(uname -m) = "ppc64le" ]; then
        log_info "To check the status, run: podman-compose ps"
        log_info "To view logs, run: podman-compose logs"
    else
        log_info "To check the status, run: docker compose ps"
        log_info "To view logs, run: docker compose logs"
    fi
}

# Run main function.
main
