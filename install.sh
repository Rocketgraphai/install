#!/bin/sh
# install.sh
set -eu
if (set -o pipefail 2>/dev/null); then
  set -o pipefail
fi

# Color codes for output.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color.

# Default ports.
DEFAULT_HTTP_PORT=80
DEFAULT_HTTPS_PORT=443

# Initialize variables with default values
HTTP_PORT=$DEFAULT_HTTP_PORT
HTTPS_PORT=$DEFAULT_HTTPS_PORT
ENTERPRISE_INSTALL=0

EXISITING_ENV=0
USE_SSL=0
USE_PODMAN=0
DOCKER_COMPOSE="docker compose"

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
    --enterprise)
      ENTERPRISE_INSTALL=1
      shift 1
      ;;
    --use-podman)
      USE_PODMAN=1
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo "Available options:"
      echo "  --http-port PORT   Specify custom HTTP port (default: $DEFAULT_HTTP_PORT)"
      echo "  --https-port PORT  Specify custom HTTPS port (default: $DEFAULT_HTTPS_PORT)"
      echo "  --enterprise       Enable multi-user enterprise installation"
      echo "  --use-podman       Use Podman instead of Docker, falling back to Docker if Podman is not installed"
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

    local tmpfile
    tmpfile=$(mktemp)

    # Run the command in the background, capture stdout/stderr
    "$@" >"$tmpfile" 2>&1 &
    local pid=$!

    local count=0
    while [ $count -lt "$timeout" ] && kill -0 "$pid" 2>/dev/null; do
        sleep 1
        count=$((count + 1))
    done

    if kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid"
        wait "$pid" 2>/dev/null
        _run_with_timeout_output=$(cat "$tmpfile")
        rm -f "$tmpfile"
        return 124  # Timeout
    fi

    wait "$pid"
    local code=$?
    _run_with_timeout_output=$(cat "$tmpfile")
    rm -f "$tmpfile"
    return $code
}

# Check system requirements.
check_requirements() {
    local container_tool="$1"
    local compose_tool="$2"
    log_info "Checking system requirements."

    # Check if Docker/Podman is installed.
    if ! command_exists $container_tool; then
        log_error "$container_tool is not installed. Please install $container_tool first."
        [ "$container_tool" = "docker" ] && log_info "Visit https://docs.docker.com/get-docker/ for installation instructions."
        exit 1
    fi

    # Check that Docker/Podman is running and the user has permissions to use it.
    if ! run_with_timeout 10 "$container_tool" ps; then
        log_error "$container_tool is either not running or this user doesn't have permission to use $container_tool. Make sure $container_tool is started. If $container_tool is running, it is likely the user doesn't have permission to use $container_tool. Either run the script as root or contact your system administrator. Output:"
        printf '%s\n' "$_run_with_timeout_output" | while IFS= read -r line; do
            log_error "  $line"
        done
        exit 1
    fi

    # Check if Docker Compose or Podman-Compose is installed.
    if ! run_with_timeout 10 $compose_tool version; then
        log_error "$container_tool is installed but $compose_tool is not. Please install $compose_tool first. Output:"
        printf '%s\n' "$_run_with_timeout_output" | while IFS= read -r line; do
            log_error "  $line"
        done
        [ "$container_tool" = "docker" ] && log_info "Visit https://docs.docker.com/compose/install/ for installation instructions."
        exit 1
    fi

    if [ "$container_tool" = "docker" ]; then
        # Check Docker Compose version.
        compose_version=$($compose_tool version --short 2>/dev/null || docker-compose --version | awk '{print $3}')
        compose_version=$(echo "$compose_version" | sed 's/[^0-9.]*//g')
        if ! version_ge "$MIN_COMPOSE_VERSION" "$compose_version"; then
            log_error "Docker Compose version $compose_version is too old. Please install Docker Compose version $MIN_COMPOSE_VERSION or higher."
            exit 1
        fi
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
        log_warn "Failed to download an env.template file."
        exit 1
    fi

    if [ -f ".env" ]; then
        EXISITING_ENV=1
        changes=0
        log_info "Checking for potentially new keys added to env.template since initial install."
        log_info "This may help identify missing entries in .env, but some may be false positives."
        while IFS= read -r line; do
            case "$line" in
                ''|\#*) continue ;;  # skip empty lines and comments
            esac
            key=$(printf "%s" "$line" | cut -d '=' -f 1)
            if ! grep -q "^$key=" .env; then
                log_warn "Key '$key' is present in env.template but not found in .env. If this key is new, consider adding it:"
                log_warn "$line"
                changes=1
            fi
        done < env.template
        rm -f env.template
        [ "$changes" -eq 0 ] && log_info "No new keys were detected."
    else
        log_info "Creating .env file from env.template."
        mv env.template .env
    fi

    # Set appropriate permissions.
    if ! chmod 600 .env >/dev/null 2>&1; then
        log_error "Failed to set permissions on .env file."
    fi
    if ! chmod 644 docker-compose.yml >/dev/null 2>&1; then
        log_error "Failed to set permissions on docker-compose.yml file."
    fi
}

# Set the values of variables needed by the script.  These get a value from the
# .env file or a default value.  Note that these variables do NOT affect the
# docker containers.  They get their values strictly from the .env file.
set_variables() {
    if [ "$EXISITING_ENV" -eq 1 ]; then
        log_info "Existing .env file found. Ignoring any new configuration values passed to the script."
        log_info "To apply new values, edit the .env file manually."
        return
    fi

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
    if grep -q '^MC_SSL_PUBLIC_CERT=' .env &&
       grep -q '^MC_SSL_PRIVATE_KEY=' .env; then
       USE_SSL=1
    fi

    # Check if xgt.lic license file exists
    if [ -f xgt.lic ]; then
        log_info "Custom license file found."
        portable_sed_i "s|^#XGT_LICENSE_FILE=/path/to/license/xgt-license.lic|XGT_LICENSE_FILE=$(pwd)/xgt.lic|" .env
    fi

    # Comment out empty authorization list to enable multi-user auth.
    if [ $ENTERPRISE_INSTALL -eq 1 ]; then
        portable_sed_i "s|^XGT_AUTH_TYPES=|#XGT_AUTH_TYPES=|" .env
    fi
}

deploy_containers() {
    local container_tool="$1"
    local compose_tool="$2"
    local arch="$3"

    if [ "$arch" = "ppc64le" ]; then
        export MC_MONGODB_IMAGE=ibmcom/mongodb-ppc64le
        portable_sed_i 's|^#MC_MONGODB_IMAGE=mongo:latest|MC_MONGODB_IMAGE=ibmcom/mongodb-ppc64le|' .env
    fi

    log_info "Pulling latest container images."
    $compose_tool pull

    if [ "$arch" = "ppc64le" ]; then
        # Ensure volume exists
        if ! $container_tool volume inspect rocketgraph_mongodb-data >/dev/null 2>&1; then
            log_info "Creating MongoDB volume..."
            if ! $container_tool volume create rocketgraph_mongodb-data >/dev/null 2>&1; then
                log_error "Failed to create MongoDB volume."
            fi
        fi

        # Fix permissions on the volume for MongoDB
        log_info "Setting correct permissions on MongoDB volume..."
        if ! $container_tool unshare chown -R 999:999 "$(podman volume inspect rocketgraph_mongodb-data -f '{{.Mountpoint}}')" >/dev/null 2>&1; then
            log_error "Failed to set permissions on MongoDB volume."
        fi

        # Check if there are existing containers that need to be removed
        if $container_tool ps -a --format "{{.Names}}" | grep -q "rocketgraph_"; then
            log_info "Removing existing Rocketgraph containers..."
            $compose_tool down >/dev/null 2>&1
        fi
    fi

    log_info "Starting containers."
    set +e
    $compose_tool up -d
    # Check if the command failed
    if [ $? -ne 0 ]; then
        log_error "If a port is already in use, you may need to change it in the .env file (e.g., MC_PORT (default: 80), MC_SSL_PORT (default: 443), etc.), then rerun the install."
        exit 1  # Exit the script with an error code
    fi
    set -e

    if [ "$container_tool" = "podman" ]; then
        if ! loginctl enable-linger >/dev/null 2>&1; then
            log_error "Failed to enable linger for user sessions."
        fi
    fi

    # Try to extract templates from a running container first
    container_id=$($container_tool ps --filter "ancestor=rocketgraph/mission-control-backend:latest" --format "{{.ID}}" | head -n 1)

    if [ -n "$container_id" ]; then
        if $container_tool cp "${container_id}:/app/templates" ./ >/dev/null 2>&1; then
            log_info "Site-config templates extracted successfully from running container."
        else
            log_info "No templates found or failed to copy from running container. Skipping."
        fi
    else
        # Fall back to running a temporary container
        if $container_tool run --rm -v "$(pwd):/output" rocketgraph/mission-control-backend:latest \
            sh -c 'cp -r /app/templates /output/' >/dev/null 2>&1; then
            log_info "Site-config templates extracted successfully from fresh container."
        else
            log_info "No site-config templates found in image or extraction failed."
        fi
    fi
}

# Main installation process.
main() {
    log_info "Starting installation process."

    command_exists docker && has_docker=1 || has_docker=0
    command_exists podman && has_podman=1 || has_podman=0

    if [ "$USE_PODMAN" = "1" ] && [ "$has_docker" = "1" ] && [ "$has_podman" = "0" ]; then
        USE_PODMAN=0
        log_warn "Podman is not installed. Docker found. Falling back to Docker."
    fi

    if [ "$USE_PODMAN" = "0" ] && [ "$has_docker" = "0" ] && [ "$has_podman" = "1" ]; then
        USE_PODMAN=1
        log_info "Docker is not installed. Podman found. Falling back to Podman."
    fi

    arch=$(uname -m)

    if [ "$USE_PODMAN" = "1" ]; then
        check_requirements podman podman-compose
    else
        if command_exists docker && docker compose version >/dev/null 2>&1; then
            DOCKER_COMPOSE="docker compose"
        else
            DOCKER_COMPOSE="docker-compose"
        fi

        check_requirements docker $DOCKER_COMPOSE
    fi

    check_installation_dir
    download_config
    set_variables

    if [ "$USE_PODMAN" = "1" ]; then
        deploy_containers podman podman-compose $arch
    else
        deploy_containers docker $DOCKER_COMPOSE $arch
    fi

    log_info "Installation completed successfully!"

    if [ "$USE_SSL" -eq 1 ]; then
      log_info "Mission Control is now running at https://localhost:${HTTPS_PORT}"
    else
      log_info "Mission Control is now running at http://localhost:${HTTP_PORT}"
    fi

    if [ "$USE_PODMAN" = "1" ]; then
        log_info "To check the status, run: podman-compose ps"
        log_info "To view logs, run: podman-compose logs"
    else
        log_info "To check the status, run: $DOCKER_COMPOSE ps"
        log_info "To view logs, run: $DOCKER_COMPOSE logs"
    fi
}

# Run main function.
main
