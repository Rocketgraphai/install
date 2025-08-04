# install.ps1

# Logging functions
function Write-InfoLog { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Green }
function Write-WarnLog { param($Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-ErrorLog { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

$ScriptVersion = "1.4.2"
Write-InfoLog "Running Script Version $ScriptVersion"

for ($i = 0; $i -lt $args.Count; $i++) {
    switch ($args[$i]) {
        '--start-dir' { $startDir = $args[++$i] }
    }
}

if ($startDir -and (Test-Path $startDir)) {
    Set-Location $startDir
} elseif ($startDir) {
    Write-WarnLog "Start directory is not set or does not exist: $startDir"
}

# Default ports
$DEFAULT_HTTP_PORT = 80
$DEFAULT_HTTPS_PORT = 443
$DEFAULT_XGT_PORT = 4367
$DEFAULT_INSTALL_DIR = Get-Location
$DEFAULT_LICENSE_LOCATION = Join-Path $DEFAULT_INSTALL_DIR 'xgt.lic'

# Initialize variables with default values
$HTTP_PORT = $DEFAULT_HTTP_PORT
$HTTPS_PORT = $DEFAULT_HTTPS_PORT
$XGT_PORT = $DEFAULT_XGT_PORT
$INSTALL_DIR = $DEFAULT_INSTALL_DIR
$LICENSE_LOCATION = $DEFAULT_LICENSE_LOCATION
$ENTERPRISE_INSTALL = $false

# Minimum required Docker Compose version
$MIN_COMPOSE_VERSION = "1.29.0"

# Pause script if running in pop-up terminal
$PAUSE_AT_END = $true

# Launch browser on success
$LAUNCH_BROWSER = $true

# Install docker if it's not installed'
$INSTALL_DOCKER = $true

# Function to display help
function Show-Help {
    Write-Host "Usage: install.ps1 [OPTIONS]"
    Write-Host "Available options:"
    Write-Host "  --http-port PORT    Specify custom HTTP port (default: $DEFAULT_HTTP_PORT)"
    Write-Host "  --https-port PORT   Specify custom HTTPS port (default: $DEFAULT_HTTPS_PORT)"
    Write-Host "  --install-dir DIR   Specify custom install location (default: $DEFAULT_INSTALL_DIR)"
    Write-Host "  --license-file DIR  Specify custom license location (default: $LICENSE_LOCATION)"
    Write-Host "  --xgt-port PORT     Specify custom XGT port (default: $DEFAULT_XGT_PORT)"
    Write-Host "  --enterprise        Enable multi-user enterprise installation"
    Write-Host "  --no-docker         Do not install docker if it's missing"
    Write-Host "  --no-browser        Do not launch the browser after setup"
    Write-Host "  --no-pause          Do not wait for input at the end"
    Write-Host "  -h, --help          Show this help message"
}

function Exit-Script {
    param (
        [int]$Code = 1
    )

    if ($PAUSE_AT_END) {
        Read-Host "Press Enter to exit..."
    }

    [System.Environment]::Exit($Code)
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
                Read-Host "Press Enter to exit..."
                exit 1
            }
        }
        '--https-port' {
            if ($i + 1 -lt $args.Count -and $args[$i + 1] -notmatch '^-') {
                $HTTPS_PORT = $args[$i + 1]
                $i++
            } else {
                Write-Error "Error: Argument for --https-port is missing"
                Read-Host "Press Enter to exit..."
                exit 1
            }
        }
        '--install-dir' {
            if ($i + 1 -lt $args.Count -and $args[$i + 1] -notmatch '^-') {
                $INSTALL_DIR = $args[$i + 1]
                $i++
            } else {
                Write-Error "Error: Argument for --install-dir is missing"
                Read-Host "Press Enter to exit..."
                exit 1
            }
        }
        '--license-file' {
            if ($i + 1 -lt $args.Count -and $args[$i + 1] -notmatch '^-') {
                $LICENSE_LOCATION = $args[$i + 1]
                $i++
            } else {
                Write-Error "Error: Argument for --install-dir is missing"
                Read-Host "Press Enter to exit..."
                exit 1
            }
        }
        '--xgt-port' {
            if ($i + 1 -lt $args.Count -and $args[$i + 1] -notmatch '^-') {
                $XGT_PORT = $args[$i + 1]
                $i++
            } else {
                Write-Error "Error: Argument for --xgt-port is missing"
                Read-Host "Press Enter to exit..."
                exit 1
            }
        }
        '--enterprise' {
            $ENTERPRISE_INSTALL = $true
        }
        '--no-docker' {
            $INSTALL_DOCKER = $false
        }
        '--no-browser' {
            $LAUNCH_BROWSER = $false
        }
        '--no-pause' {
            $PAUSE_AT_END = $false
        }
        '-h' {
            Show-Help
            exit 0
        }
        '--help' {
            Show-Help
            exit 0
        }
        '--start-dir' {
            $i++
            #Ignore
        }
        default {
            Write-Error "Unknown option: $($args[$i])"
            Write-Host "Use -h or --help to see available options"
            Read-Host "Press Enter to exit..."
            exit 1
        }
    }
}

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

        # Save to temp file and elevate
        $tempFile = [IO.Path]::Combine($env:TEMP, "rocketgraph_installer.ps1")
        Set-Content -Path $tempFile -Value $scriptContent -Encoding UTF8 > $null
        $quotedArgs = @()
        foreach ($arg in $args) { $quotedArgs += "`"$arg`"" }
        $quotedArgs += "`"--start-dir`""
        $quotedArgs += "`"$DEFAULT_INSTALL_DIR`""
        $allArgs = @("-ExecutionPolicy", "Bypass", "-File", "`"$tempFile`"") + $quotedArgs

        Start-Process powershell -ArgumentList $allArgs -WorkingDirectory $DEFAULT_INSTALL_DIR -Verb RunAs
        exit 1
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
    if ((-not (Ensure-WSL2))) {
        Exit-Script 1
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $url = "https://desktop.docker.com/win/main/amd64/Docker Desktop Installer.exe"
    $dockerInstaller = "$env:TEMP\DockerDesktopInstaller.exe"
    Write-InfoLog "Downloading Docker Desktop..."
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($url, $dockerInstaller)
    Write-InfoLog "Installing Docker Desktop (may require reboot)..."
    Start-Process -FilePath $dockerInstaller -ArgumentList "install", "--quiet", '--accept-license' -Wait
    # Refresh environment variables from registry
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function Is-RebootPending {
    try {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64
        )
        $subKey = $baseKey.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending")
        return $subKey -ne $null
    } catch {
        return $false
    }
}

function Ensure-WSL2 {
    # Minimum Windows build for WSL2 is 19041
    if ([System.Environment]::OSVersion.Version.Build -lt 19041) {
        Write-ErrorLog "WSL2 requires Windows 10 version 2004 (build 19041) or later."
        return $false
    }

    $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
    $vmFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform

    $needsEnable = $false

    if ($wslFeature.State -ne "Enabled") {
        Write-InfoLog "Enabling WSL feature..."
        try {
            Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart -ErrorAction Stop
            $needsEnable = $true
        } catch {
            Write-ErrorLog ("Failed to enable WSL. The component store may be unavailable in this environment (e.g., Windows Sandbox or VM without nested virtualization).`nError details: {0}" -f $_.Exception.Message)
            return $false
        }
    }

    if ($vmFeature.State -ne "Enabled") {
        Write-InfoLog "Enabling VirtualMachinePlatform for WSL2..."
        try {
            Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart -ErrorAction Stop
            $needsEnable = $true
        } catch {
            Write-ErrorLog ("Failed to enable VirtualMachinePlatform. This may be due to missing virtualization support or a restricted environment.`nError details: {0}" -f $_.Exception.Message)
            return $false
        }
    }

    # Try setting WSL2 as the default
    try {
        wsl --set-default-version 2 > $null 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "wsl.exe exited with code $LASTEXITCODE"
        }
        Write-InfoLog "WSL2 set as the default version."
    } catch {
        Write-WarnLog "wsl --set-default-version failed. Attempting to detect if 'wsl --update' is supported..."

        # Check if 'wsl --update' exists
        $hasWSLUpdate = $false
        try {
            $wslHelp = & wsl --help 2>&1
            if ($wslHelp -match '--update') {
                $hasWSLUpdate = $true
            }
        } catch {
            Write-ErrorLog "WSL is not available: $_"
            return $false
        }

        if ($hasWSLUpdate) {
            try {
                Write-InfoLog "Running 'wsl --update'..."
                $output = & wsl --update 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-WarnLog "wsl --update failed with exit code $LASTEXITCODE.`n$output"
                }
                Write-InfoLog "WSL updated successfully."
            } catch {
                Write-ErrorLog "Failed to run 'wsl --update'. Error: $_"
                return $false
            }
        } else {
            try {
                Write-InfoLog "'wsl --update' not supported. Attempting 'wsl --install --no-distribution'..."
                $output = & wsl --install --no-distribution 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-WarnLog "wsl --install failed with exit code $LASTEXITCODE.`n$output"
                }
                Write-InfoLog "WSL installed successfully (no distribution)."
            } catch {
                Write-ErrorLog "Failed to run 'wsl --install --no-distribution'. Error: $_"
                return $false
            }
        }
    }

    if ($needsEnable) {
        Write-ErrorLog "WSL2 features were just enabled. Please restart your system to complete installation."
        return $false
    }

    if (Is-RebootPending) {
        Write-ErrorLog "A system reboot is required to finalize the WSL2 setup."
        Exit-Script 2
        return $false
    }

    return $true
}

# Check system requirements
function Test-Requirements {
    Write-InfoLog "Checking system requirements..."

    # Check Docker
    if (-not (Get-Command "docker" -ErrorAction SilentlyContinue)) {
        if ($isWindowsPlat -and $INSTALL_DOCKER) {
            Write-InfoLog "Docker not found..."
            Install-Docker
        } else {
            Write-ErrorLog "Docker is not installed. Please install Docker Desktop for Windows first."
            Write-InfoLog "Visit https://docs.docker.com/desktop/windows/install/ for installation instructions"
            Exit-Script 1
        }
    }

    if ($isWindowsPlat -and (-not (Ensure-WSL2))) {
        Exit-Script 1
    }

    # Ensure Docker is running
    Write-InfoLog "Ensuring Docker is running..."

    $dockerRunning = & docker info > $null 2>&1

    if ($LASTEXITCODE -ne 0) {
        if(-not $isWindowsPlat) {
            Write-ErrorLog "Docker not running."
            Exit-Script 1
        }

        Write-InfoLog "Docker is not running. Attempting to start Docker Desktop..."

        # Try to start Docker Desktop
        Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"

        # Wait for it to become responsive
        $maxAttempts = 60
        $attempt = 0
        while ($attempt -lt $maxAttempts) {
            Start-Sleep -Seconds 2
            & docker info > $null 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-InfoLog "Docker is now running."
                break
            }
            $attempt++
        }

        if ($LASTEXITCODE -ne 0) {
            Write-ErrorLog "Docker failed to start or become ready within timeout."
            Exit-Script 1
        }
    } else {
        Write-InfoLog "Docker is already running."
    }

    # Check Docker Compose version (with output suppression)
    $composeVersion = @(docker compose version --short 2>$null)[0] -replace '[^0-9.]'
    if (-not (Test-VersionGreaterOrEqual $composeVersion $MIN_COMPOSE_VERSION)) {
        Write-ErrorLog "Docker Compose version $composeVersion is too old. Please install Docker Compose version $MIN_COMPOSE_VERSION or higher."
        Exit-Script 1
    }

    # Check disk space (1GB = 1073741824 bytes)
    $drive = Get-PSDrive -Name (Get-Location).Drive.Name
    if ($drive.Free -lt 1GB) {
        Write-ErrorLog "Insufficient disk space. Please ensure at least 1GB of free space."
        Exit-Script 1
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
        Exit-Script 1
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
        Exit-Script 1
    }

    if ($version.Build -lt 18362) {
        Write-ErrorLog "Windows 10 version 1903 or higher is required"
        Exit-Script 1
    }
}

# Check for port conflicts
function Test-Settings {
    Write-InfoLog "Checking settings for issues..."

    if (-not (Test-Path $LICENSE_LOCATION) -and ($LICENSE_LOCATION -ne $DEFAULT_LICENSE_LOCATION)) {
        Write-ErrorLog "Missing license file at: $LICENSE_LOCATION (custom path)"
        Exit-Script 1
    }

    $portsToCheck = @(
        $HTTP_PORT,
        $XGT_PORT
    )

    foreach ($port in $portsToCheck) {
        if (Test-PortInUse $port) {
            Write-ErrorLog "Port $port is already in use. Please stop the existing service or specify a different port."
            Exit-Script 1
        }
    }
}

# Create installation directory
function Initialize-InstallationDirectory {
    New-Item -ItemType Directory -Path $INSTALL_DIR -Force | Out-Null
    Set-Location -Path $INSTALL_DIR
    Write-InfoLog "Using installation directory at $INSTALL_DIR..."
}

function Set-EnvVariables {
    Write-InfoLog "Setting up .env configuration file..."

    $envFile = ".env"

    if (Test-Path $envFile) {
        $envContent = Get-Content $envFile

        if ($envContent -match '^#MC_PORT=' -and $HTTP_PORT -ne $DEFAULT_HTTP_PORT) {
            Write-InfoLog "Using non-standard HTTP_PORT=$HTTP_PORT"
            $envContent = $envContent -replace "^#MC_PORT=$DEFAULT_HTTP_PORT", "MC_PORT=$HTTP_PORT"
        }

        if ($envContent -match '^#MC_SSL_PORT=' -and $HTTPS_PORT -ne $DEFAULT_HTTPS_PORT) {
            Write-InfoLog "Using non-standard HTTPS_PORT=$HTTPS_PORT"
            $envContent = $envContent -replace "^#MC_SSL_PORT=$DEFAULT_HTTPS_PORT", "MC_SSL_PORT=$HTTPS_PORT"
        }

        if ($envContent -match '^#XGT_PORT=' -and $XGT_PORT -ne $DEFAULT_XGT_PORT) {
            Write-InfoLog "Using non-standard XGT_PORT=$XGT_PORT"
            $envContent = $envContent -replace "^#XGT_PORT=$DEFAULT_XGT_PORT", "XGT_PORT=$XGT_PORT"
        }

        if ($envContent -match '^#XGT_LICENSE_FILE=' -and (Test-Path $LICENSE_LOCATION)) {
            Write-InfoLog "Custom license file found."
            $escapedPath = $LICENSE_LOCATION -replace '\\', '\\\\'
            $envContent = $envContent -replace '^#XGT_LICENSE_FILE=.*', "XGT_LICENSE_FILE=`"$escapedPath`""
        }

        if ($ENTERPRISE_INSTALL) {
            Write-InfoLog "Enterprise mode enabled."
            $envContent = $envContent -replace '^XGT_AUTH_TYPES=', '#XGT_AUTH_TYPES='
        }

        $USE_SSL = 0
        if ($envContent -match '^MC_SSL_PUBLIC_CERT=' -and $envContent -match '^MC_SSL_PRIVATE_KEY=') {
            $USE_SSL = 1
        }

        $envContent | Set-Content $envFile
    } else {
        Write-WarnLog ".env file not found."
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
        Exit-Script 1
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
        Exit-Script 1
    }
    $null = Receive-Job $pullJob
    Remove-Job $pullJob

    Write-InfoLog "Starting containers..."
    $null = docker compose up -d 2>&1 | Tee-Object -Variable dockerOutput
    if ($LASTEXITCODE -ne 0) {
      Write-ErrorLog "Failed to start containers. Error: $dockerOutput"
      Exit-Script 1
    }

    # Extract site-config templates from the running backend container
    $containerId = docker ps --filter "ancestor=rocketgraph/mission-control-backend:latest" --format "{{.ID}}" | Select-Object -First 1

    if (-not $containerId) {
        Write-ErrorLog "Backend container not found for template extraction."
        return
    }

    Write-InfoLog "Attempting to copy site-config templates from container..."
    docker cp "${containerId}:/app/templates" "$INSTALL_DIR" 2>$null

    if ($LASTEXITCODE -eq 0) {
        Write-InfoLog "Site-config templates extracted successfully."
    } else {
        Write-InfoLog "No site-config templates found in the container or copy failed."
    }
}

# Main installation process
function Start-Installation {
    Write-InfoLog "Starting installation process..."

    if ($isWindowsPlat) {
      Test-WindowsRequirements
    }
    Test-Requirements
    Test-Settings
    Initialize-InstallationDirectory
    Get-ConfigurationFiles
    Start-Containers

    Write-InfoLog "Installation completed successfully!"
    Write-InfoLog "Your application is now running at http://localhost:$HTTP_PORT"
    Write-InfoLog "To check the status, run: docker compose ps"
    Write-InfoLog "To view logs, run: docker compose logs"
    if ($LAUNCH_BROWSER) {
        Write-InfoLog "Launching browser..."
        $timeout = 30
        $portReady = $false

        for ($i = 0; $i -lt $timeout; $i++) {
            try {
                $tcpClient = New-Object System.Net.Sockets.TcpClient
                $tcpClient.Connect("localhost", $HTTP_PORT)
                $tcpClient.Close()
                $portReady = $true
                break
            } catch {
                Start-Sleep -Seconds 1
            }
        }
        Start-Process "http://localhost:$HTTP_PORT"
    }
}

try {
    # Run main function
    Start-Installation
} catch {
    Write-ErrorLog "Script error: $_"
} finally {
    if ($PAUSE_AT_END) {
        Read-Host "Press Enter to exit..."
    }
}
