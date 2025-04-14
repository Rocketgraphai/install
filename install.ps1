# install.ps1

# Default ports
$DEFAULT_HTTP_PORT = 80
$DEFAULT_HTTPS_PORT = 443
$DEFAULT_XGT_PORT = 4367

# Initialize variables with default values
$HTTP_PORT = $DEFAULT_HTTP_PORT
$HTTPS_PORT = $DEFAULT_HTTPS_PORT
$XGT_PORT = $DEFAULT_XGT_PORT

# Minimum required Docker Compose version
$MIN_COMPOSE_VERSION = "1.29.0"

# Pause script if running in pop-up terminal
$PAUSE_AT_END = $true

# Launch browser on success
$LAUNCH_BROWSER = $true

# Function to display help
function Show-Help {
    Write-Host "Usage: install.ps1 [OPTIONS]"
    Write-Host "Available options:"
    Write-Host "  --http-port PORT   Specify custom HTTP port (default: $DEFAULT_HTTP_PORT)"
    Write-Host "  --https-port PORT  Specify custom HTTPS port (default: $DEFAULT_HTTPS_PORT)"
    #Write-Host "  --xgt-port PORT    Specify custom XGT port (default: $DEFAULT_XGT_PORT)"
    Write-Host "  --no-browser       Do not launch the browser after setup"
    Write-Host "  --no-pause         Do not wait for input at the end"
    Write-Host "  -h, --help         Show this help message"
}

# Parse command-line arguments
for ($i = 0; $i -lt $args.Count; $i++) {
    switch ($args[$i]) {
        '--http-port' {
            if ($i + 1 -lt $args.Count -and $args[$i + 1] -notmatch '^-') {
                $HTTP_PORT = $args[$i + 1]
                $i++
            } else {
                Write-Error "Error: Argument for --http-port is missing"
                exit 1
            }
        }
        '--https-port' {
            if ($i + 1 -lt $args.Count -and $args[$i + 1] -notmatch '^-') {
                $HTTPS_PORT = $args[$i + 1]
                $i++
            } else {
                Write-Error "Error: Argument for --https-port is missing"
                exit 1
            }
        }<#
        '--xgt-port' {
            if ($i + 1 -lt $args.Count -and $args[$i + 1] -notmatch '^-') {
                $XGT_PORT = $args[$i + 1]
                $i++
            } else {
                Write-Error "Error: Argument for --xgt-port is missing"
                exit 1
            }
        }#>
        '-h' {
            Show-Help
            exit 0
        }
        '--help' {
            Show-Help
            exit 0
        }
        '--no-browser' {
            $LAUNCH_BROWSER = $false
        }
        '--no-pause' {
            $PAUSE_AT_END = $false
        }
        default {
            Write-Error "Unknown option: $($args[$i])"
            Write-Host "Use -h or --help to see available options"
            exit 1
        }
    }
}

# Logging functions
function Write-InfoLog { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Green }
function Write-WarnLog { param($Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-ErrorLog { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

function Get-OSPlatform {
    # Try PowerShell Core method first
    if (Test-Path variable:IsWindows) {
        if ($IsWindows) { return "Windows" }
        elseif ($IsLinux) { return "Linux" }
        elseif ($IsMacOS) { return "MacOS" }
    }
    # Fall back to .NET method for PowerShell 5.1
    else {
        $platform = [System.Environment]::OSVersion.Platform
        if ($platform -match "Win") { return "Windows" }
        # This will never execute in PS 5.1, but included for completeness
        elseif ($platform -match "Unix") { return "Linux/Unix" }
        elseif ($platform -match "MacOS") { return "MacOS" }
    }
    return "Unknown"
}

$global:isWindowsPlat = (Get-OSPlatform) -eq "Windows"

# Check if script is run as administrator
$isAdmin = $false
if ($isWindowsPlat) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} elseif ($IsLinux -or $IsMacOS) {
    $isAdmin = [int](id -u) -eq 0
}
if (-not $isAdmin) {
    if ($isWindowsPlat) {
        # Determine script content source
        $scriptPath = $MyInvocation.MyCommand.Path
        if (-not $scriptPath) {
            # Script was run via iex/iwr, so re-download it manually
            $response = Invoke-WebRequest -Uri 'https://install.rocketgraph.com/install.ps1' -UseBasicParsing
            $reader = New-Object System.IO.StreamReader($response.RawContentStream)
            $scriptContent = $reader.ReadToEnd()
            $reader.Close()
        } else {
            $scriptContent = Get-Content -Raw -Path $scriptPath
        }


        #Write-InfoLog $scriptContent
        # Save to temp file and elevate
        $tempFile = [IO.Path]::Combine($env:TEMP, "rocketgraph_installer.ps1")
        Set-Content -Path $tempFile -Value $scriptContent -Encoding UTF8 > $null  # <== suppress output

        Start-Process powershell "-ExecutionPolicy Bypass -File `"$tempFile`"" -Verb RunAs
        exit
    } else {
        Write-ErrorLog "This script must be run as Administrator"
    }
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
    if ($isWindowsPlat) {
        # Windows: Use Get-NetTCPConnection
        return (Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue) -ne $null
    } else {
        # Linux/macOS: Use lsof
        $result = lsof -iTCP:$Port -sTCP:LISTEN
        return ($result -ne $null) -and ($result.Count -gt 0)
    }
}

# Function to compare versions
function Test-VersionGreaterOrEqual {
    param($Version1, $Version2)
    return ([System.Version]$Version1 -ge [System.Version]$Version2)
}

function Install-Docker {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $url = "https://desktop.docker.com/win/main/amd64/Docker Desktop Installer.exe"
    $dockerInstaller = "$env:TEMP\DockerDesktopInstaller.exe"
    Write-InfoLog "Downloading Docker Desktop..."
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($url, $dockerInstaller)
    #$dockerInstaller = "$env:TEMP\DockerDesktopInstaller.exe"
    #$url = "https://desktop.docker.com/win/main/amd64/Docker Desktop Installer.exe"
    #Invoke-WebRequest -Uri $url -OutFile $dockerInstaller
    Write-InfoLog "Installing Docker Desktop..."
    Start-Process -FilePath $dockerInstaller -ArgumentList "install" -Wait
}

function Ensure-WSL2 {
    # Minimum Windows build for WSL2 is 19041
    if ([System.Environment]::OSVersion.Version.Build -lt 19041) {
        Write-InfoLog "WSL2 requires Windows 10 version 2004 or later."
        return $false
    }

    $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
    $vmFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform

    $needsEnable = $false

    if ($wslFeature.State -ne "Enabled") {
        Write-InfoLog "Enabling WSL feature..."
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart
        $needsEnable = $true
    }

    if ($vmFeature.State -ne "Enabled") {
        Write-InfoLog "Enabling VirtualMachinePlatform for WSL2..."
        Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
        $needsEnable = $true
    }

    if ($needsEnable) {
        Write-InfoLog "Features were enabled. Please restart your system to complete WSL2 installation."
        return $false
    }

    try {
        wsl --set-default-version 2 2>$null
        Write-InfoLog "WSL2 set as the default version."
    } catch {
        Write-InfoLog "Failed to set WSL2 as default. Try restarting or check WSL installation status."
        return $false
    }

    return $true
}

# Check system requirements
function Test-Requirements {
    Write-InfoLog "Checking system requirements..."

    if ($isWindowsPlat) {
        #Ensure-WSL2
    }

    # Check Docker
    if (-not (Get-Command "docker" -ErrorAction SilentlyContinue)) {
        if ($isWindowsPlat) {
            Write-InfoLog "Docker not found..."
            Install-Docker
        } else {
            Write-ErrorLog "Docker is not installed. Please install Docker Desktop for Windows first."
            Write-InfoLog "Visit https://docs.docker.com/desktop/windows/install/ for installation instructions"
            exit 1
        }
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
        $response = Invoke-WebRequest -Uri "https://install.rocketgraph.com" -Method Head
        if ($response.StatusCode -ne 200) {
            throw "Non-200 status code"
        }
    }
    catch {
        Write-ErrorLog "Network connectivity issue. Unable to reach https://install.rocketgraph.com"
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
        $HTTP_PORT,
        $XGT_PORT
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

function Set-EnvVariables {
    Write-Host "Setting up .env configuration file..."

    $envFile = ".env"

    if (Test-Path $envFile) {
        $envContent = Get-Content $envFile

        if ($envContent -match '^#MC_PORT=' -and $HTTP_PORT -ne $DEFAULT_HTTP_PORT) {
            Write-Host "Using non-standard HTTP_PORT=$HTTP_PORT"
            $envContent = $envContent -replace "^#MC_PORT=$DEFAULT_HTTP_PORT", "MC_PORT=$HTTP_PORT"
        }

        if ($envContent -match '^#MC_SSL_PORT=' -and $HTTPS_PORT -ne $DEFAULT_HTTPS_PORT) {
            Write-Host "Using non-standard HTTPS_PORT=$HTTPS_PORT"
            $envContent = $envContent -replace "^#MC_SSL_PORT=$DEFAULT_HTTPS_PORT", "MC_SSL_PORT=$HTTPS_PORT"
        }

        if ($envContent -match '^#MC_XGT_PORT=' -and $XGT_PORT -ne $DEFAULT_XGT_PORT) {
            Write-Host "Using non-standard XGT_PORT=$XGT_PORT"
            $envContent = $envContent -replace "^#MC_XGT_PORT=$DEFAULT_XGT_PORT", "MC_XGT_PORT=$XGT_PORT"
        }

        $USE_SSL = 0
        if ($envContent -match '^MC_SSL_PUBLIC_CERT=' -and $envContent -match '^MC_SSL_PRIVATE_KEY=') {
            $USE_SSL = 1
        }

        $envContent | Set-Content $envFile
    } else {
        Write-Warning ".env file not found."
    }
}

# Download configuration files
function Get-ConfigurationFiles {
    $downloadUrl = "https://raw.githubusercontent.com/Rocketgraphai/rocketgraph/main"
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
    Set-EnvVariables
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

    if ($isWindowsPlat) {
      Test-WindowsRequirements
    }
    Test-Requirements
    Test-Ports
    Initialize-InstallationDirectory
    Get-ConfigurationFiles
    Start-Containers

    Write-InfoLog "Installation completed successfully!"
    Write-InfoLog "Your application is now running at http://localhost:$HTTP_PORT"
    Write-InfoLog "To check the status, run: docker compose ps"
    Write-InfoLog "To view logs, run: docker compose logs"
    if ($LAUNCH_BROWSER) {
        Write-InfoLog "Launching browser..."
        Start-Process "http://localhost:$HTTP_PORT"
    }
}

try {
    # Run main function
    Start-Installation
} catch {
    Write-Error "Script error: $_"
} finally {
    if ($PAUSE_AT_END) {
        Read-Host "Press Enter to exit..."
    }
}
