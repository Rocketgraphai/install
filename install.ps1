# install.ps1

# Default ports
$DEFAULT_PORT = 80
$DEFAULT_XGT_PORT = 4367

# Minimum required Docker Compose version
$MIN_COMPOSE_VERSION = "1.29.0"

# Logging functions
function Write-InfoLog { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Green }
function Write-WarnLog { param($Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-ErrorLog { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

# Check if script is run as administrator
$isAdmin = $false
if ($IsWindows) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} elseif ($IsLinux -or $IsMacOS) {
    $isAdmin = [int](id -u) -eq 0
}
if (-not $isAdmin) {
    Write-ErrorLog "This script must be run as Administrator"
    exit 1
}

# Function to check if a command exists
function Test-Command {
    param($CommandName)
    $null -ne (Get-Command $CommandName -ErrorAction SilentlyContinue)
}

# Function to check if a port is in use
function Test-PortInUse {
    param([int]$Port)
    if ($IsWindows) {
        # Windows: Use Get-NetTCPConnection
        return (Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue) -ne $null
    } else {
        # Linux/macOS: Use lsof
        return ($result -ne $null) -and ($result.Count -gt 0)
    }
}

# Function to compare versions
function Test-VersionGreaterOrEqual {
    param($Version1, $Version2)
    return ([System.Version]$Version1 -ge [System.Version]$Version2)
}

# Check system requirements
function Test-Requirements {
    Write-InfoLog "Checking system requirements..."

    # Check Docker
    if (-not (Get-Command "docker" -ErrorAction SilentlyContinue)) {
        Write-ErrorLog "Docker is not installed. Please install Docker Desktop for Windows first."
        Write-InfoLog "Visit https://docs.docker.com/desktop/windows/install/ for installation instructions"
        exit 1
    }

    # Check if Docker is running (with output suppression)
    try {
        $null = docker version 2>$null
    }
    catch {
        Write-ErrorLog "Docker is not running or not responding. Please start Docker first."
        exit 1
    }

    # Check Docker Compose version (with output suppression)
    $composeVersion = @(docker compose version --short 2>$null)[0] -replace '[^0-9.]'
    if (-not (Test-VersionGreaterOrEqual $composeVersion $MIN_COMPOSE_VERSION)) {
        Write-ErrorLog "Docker Compose version $composeVersion is too old. Please install Docker Compose version $MIN_COMPOSE_VERSION or higher."
        exit 1
    }

    # Check disk space (1GB = 1073741824 bytes)
    $drive = Get-PSDrive -Name (Get-Location).Drive.Name
    if ($drive.Free -lt 1073741824) {
        Write-ErrorLog "Insufficient disk space. Please ensure at least 1GB of free space."
        exit 1
    }

    # Check network connectivity
    try {
        $response = Invoke-WebRequest -Uri "https://install.rocketgraph.ai" -Method Head
        if ($response.StatusCode -ne 200) {
            throw "Non-200 status code"
        }
    }
    catch {
        Write-ErrorLog "Network connectivity issue. Unable to reach https://install.rocketgraph.ai"
        exit 1
    }
}

# Function to check Windows requirements
function Test-WindowsRequirements {
    Write-InfoLog "Checking Windows requirements..."

    # Check Windows version
    $osInfo = Get-WmiObject -Class Win32_OperatingSystem
    $version = [System.Version]$osInfo.Version

    if ($version.Major -lt 10) {
        Write-ErrorLog "Windows 10 or higher is required"
        exit 1
    }

    if ($version.Build -lt 18362) {
        Write-ErrorLog "Windows 10 version 1903 or higher is required"
        exit 1
    }

    # Check if WSL is installed (required for Home edition)
    if ($osInfo.Caption -like "*Home*") {
        $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
        if (-not $wsl) {
            Write-ErrorLog "WSL 2 is required for Windows Home edition"
            Write-InfoLog "Visit https://docs.microsoft.com/windows/wsl/install for installation instructions"
            exit 1
        }
    }
}

# Check for port conflicts
function Test-Ports {
    Write-InfoLog "Checking for port conflicts..."

    $portsToCheck = @(
        $DEFAULT_PORT,
        $DEFAULT_XGT_PORT
    )

    foreach ($port in $portsToCheck) {
        if (Test-PortInUse $port) {
            Write-WarnLog "Port $port is already in use. Please stop the existing service or specify a different port."
            exit 1
        }
    }
}

# Create installation directory
function Initialize-InstallationDirectory {
    $installDir = Get-Location
    Write-InfoLog "Using installation directory at ${installDir}..."
}

# Download configuration files
function Get-ConfigurationFiles {
    $downloadUrl = "https://install.rocketgraph.ai"
    Write-InfoLog "Downloading configuration files from ${downloadUrl}..."

    try {
        Invoke-WebRequest "${downloadUrl}/docker-compose.yml" -OutFile "docker-compose.yml"
    }
    catch {
        Write-ErrorLog "Failed to download docker-compose.yml"
        exit 1
    }

    try {
        Invoke-WebRequest "${downloadUrl}/env.template" -OutFile "env.template"
        if (Test-Path ".env") {
            Write-InfoLog "Merging env.template with existing .env file..."
            $existing = Get-Content ".env"
            $template = Get-Content "env.template"
            foreach ($line in $template) {
                $key = ($line -split '=')[0]
                if (-not ($existing -match "^$key=")) {
                    Add-Content ".env" $line
                }
            }
        }
        else {
            Write-InfoLog "Creating .env file from env.template..."
            Move-Item -Path "env.template" -Destination ".env"
        }
    }
    catch {
        Write-WarnLog "Failed to download env.template"
    }
}

# Pull and start containers (with output suppression)
function Start-Containers {
    Write-InfoLog "Pulling latest container images..."
    $pullJob = Start-Job -ScriptBlock { docker compose pull 2>$null }
    if (-not (Wait-Job $pullJob -Timeout 300)) {
        Write-ErrorLog "Failed to pull container images (timeout)"
        exit 1
    }
    $null = Receive-Job $pullJob
    Remove-Job $pullJob

    Write-InfoLog "Starting containers..."
    $null = docker compose up -d 2>&1 | Tee-Object -Variable dockerOutput
    if ($LASTEXITCODE -ne 0) {
      Write-ErrorLog "Failed to start containers. Error: $dockerOutput"
      exit 1
    }
}

# Main installation process
function Start-Installation {
    Write-InfoLog "Starting installation process..."

    if ($IsWindows) {
      Test-WindowsRequirements
    }
    Test-Requirements
    Test-Ports
    Initialize-InstallationDirectory
    Get-ConfigurationFiles
    Start-Containers

    Write-InfoLog "Installation completed successfully!"
    Write-InfoLog "Your application is now running at http://localhost:$DEFAULT_PORT"
    Write-InfoLog "To check the status, run: docker compose ps"
    Write-InfoLog "To view logs, run: docker compose logs"
}

# Run main function
Start-Installation
