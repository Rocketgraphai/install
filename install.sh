#!/bin/sh
# install.sh

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default repository URL (can be overridden by environment variable)
: "${MISSION_CONTROL_REPO:=trovares/mission-control}"

# Log functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if script is run with sudo/root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root or with sudo"
    exit 1
fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
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

    # Check Docker Compose
    if ! command_exists docker compose && ! command_exists docker-compose; then
        log_error "Docker Compose is not installed. Please install Docker Compose first."
        log_info "Visit https://docs.docker.com/compose/install/ for installation instructions"
        exit 1
    fi

    # Check curl
    if ! command_exists curl; then
        log_error "curl is not installed. Please install curl first."
        exit 1
    fi
}

# Create installation directory
setup_installation_dir() {
    local install_dir="/opt/myapp"
    log_info "Creating installation directory at ${install_dir}..."

    mkdir -p "${install_dir}"
    if [ ! -d "${install_dir}" ]; then
        log_error "Failed to create installation directory"
        exit 1
    fi

    cd "${install_dir}" || exit 1
}

# Download configuration files
download_config() {
    local github_raw_url="https://raw.githubusercontent.com/${MISSION_CONTROL_REPO}/main"

    log_info "Downloading configuration files from ${github_raw_url}..."

    # Download docker-compose.yml
    if ! curl -sSL "${github_raw_url}/docker-compose.yml" -o docker-compose.yml; then
        log_error "Failed to download docker-compose.yml"
        exit 1
    fi

    # Download .env template if it exists
    curl -sSL "${github_raw_url}/.env.template" -o .env 2>/dev/null

    # Set appropriate permissions
    chmod 600 .env 2>/dev/null
    chmod 644 docker-compose.yml
}

# Pull and start containers
deploy_containers() {
    log_info "Pulling latest container images..."
    if ! docker compose pull; then
        log_error "Failed to pull container images"
        exit 1
    }

    log_info "Starting containers..."
    if ! docker compose up -d; then
        log_error "Failed to start containers"
        exit 1
    }
}

# Main installation process
main() {
    log_info "Starting installation process..."

    check_requirements
    setup_installation_dir
    download_config
    deploy_containers

    log_info "Installation completed successfully!"
    log_info "Your application is now running at http://localhost:YOUR_PORT"
    log_info "To check the status, run: docker compose ps"
    log_info "To view logs, run: docker compose logs"
}

# Run main function
main
