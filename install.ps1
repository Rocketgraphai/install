# install.ps1

# Logging functions
function Write-InfoLog { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Green }
function Write-WarnLog { param($Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-ErrorLog { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

# Check if script is run as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-ErrorLog "This script must be run as Administrator"
    exit 1
}

# Function to check if a command exists
function Test-Command {
    param($CommandName)
    $null -ne (Get-Command $CommandName -ErrorAction SilentlyContinue)
}

# Check system requirements
function Test-Requirements {
    Write-InfoLog "Checking system requirements..."
    
    # Check Docker
    if (-not (Test-Command "docker")) {
        Write-ErrorLog "Docker is not installed. Please install Docker Desktop for Windows first."
        Write-InfoLog "Visit https://docs.docker.com/desktop/windows/install/ for installation instructions"
        exit 1
    }

    # Check Docker Compose
    if (-not (Test-Command "docker") -or -not (docker compose version 2>&1)) {
        Write-ErrorLog "Docker Compose is not available. Please ensure Docker Desktop is properly installed."
        exit 1
    }
}

# Create installation directory
function Initialize-InstallationDirectory {
    $installDir = "C:\Program Files\MyApp"
    Write-InfoLog "Creating installation directory at ${installDir}..."
    
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    if (-not (Test-Path $installDir)) {
        Write-ErrorLog "Failed to create installation directory"
        exit 1
    }
    
    Set-Location $installDir
}

# Download configuration files
function Get-ConfigurationFiles {
    $githubRawUrl = "https://raw.githubusercontent.com/yourusername/yourrepo/main"
    
    Write-InfoLog "Downloading configuration files..."
    
    # Download docker-compose.yml
    try {
        Invoke-WebRequest "${githubRawUrl}/docker-compose.yml" -OutFile "docker-compose.yml"
    }
    catch {
        Write-ErrorLog "Failed to download docker-compose.yml"
        exit 1
    }

    # Download .env template if it exists
    try {
        Invoke-WebRequest "${githubRawUrl}/.env.template" -OutFile ".env" -ErrorAction SilentlyContinue
    }
    catch {
        Write-WarnLog ".env template not found, skipping..."
    }
}

# Pull and start containers
function Start-Containers {
    Write-InfoLog "Pulling latest container images..."
    docker compose pull
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorLog "Failed to pull container images"
        exit 1
    }

    Write-InfoLog "Starting containers..."
    docker compose up -d
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorLog "Failed to start containers"
        exit 1
    }
}

# Main installation process
function Start-Installation {
    Write-InfoLog "Starting installation process..."
    
    Test-Requirements
    Initialize-InstallationDirectory
    Get-ConfigurationFiles
    Start-Containers
    
    Write-InfoLog "Installation completed successfully!"
    Write-InfoLog "Your application is now running at http://localhost:YOUR_PORT"
    Write-InfoLog "To check the status, run: docker compose ps"
    Write-InfoLog "To view logs, run: docker compose logs"
}

# Run main function
Start-Installation
