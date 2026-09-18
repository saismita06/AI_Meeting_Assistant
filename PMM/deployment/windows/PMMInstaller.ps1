param(
    [string]$InstallRoot = "$env:ProgramData\PMM\AI-Meeting-Assistant",
    [string]$AppUrl = "http://localhost:8899",
    [string]$OllamaModel = "qwen2.5:3b",
    [int]$TimeoutSeconds = 1200
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$StateRoot = "$env:ProgramData\PMM"
$DownloadRoot = Join-Path $StateRoot "Downloads"
$LogRoot = Join-Path $StateRoot "Logs"
New-Item -ItemType Directory -Force -Path $DownloadRoot, $LogRoot | Out-Null
$LogFile = Join-Path $LogRoot ("installer-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $LogFile -Append | Out-Null

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    Write-Host ("[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message)
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-CommandExists {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-FromUrl {
    param(
        [string]$Name,
        [string]$Url,
        [string]$InstallerPath,
        [string[]]$Arguments
    )
    if (-not (Test-Path $InstallerPath)) {
        Write-Log "Downloading $Name"
        Invoke-WebRequest -Uri $Url -OutFile $InstallerPath -UseBasicParsing
    } else {
        Write-Log "Reusing downloaded $Name installer"
    }
    Write-Log "Installing $Name"
    $process = Start-Process -FilePath $InstallerPath -ArgumentList $Arguments -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010, 1641)) {
        throw "$Name installer failed with exit code $($process.ExitCode)"
    }
}

function Ensure-Wsl2 {
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($wsl) {
        try {
            wsl --status *> $null
            Write-Log "WSL is already available"
            return
        } catch {
            Write-Log "WSL command exists but needs initialization"
        }
    }

    Write-Log "Enabling WSL2 Windows features"
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart | Out-Null
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart | Out-Null
    try {
        wsl --set-default-version 2
    } catch {
        Write-Log "WSL default version could not be set yet; a reboot may be required" "WARN"
    }
}

function Ensure-Git {
    if (Test-CommandExists "git") {
        Write-Log "Git is already installed"
        return
    }
    $path = Join-Path $DownloadRoot "Git-64-bit.exe"
    Install-FromUrl `
        -Name "Git for Windows" `
        -Url "https://github.com/git-for-windows/git/releases/latest/download/Git-64-bit.exe" `
        -InstallerPath $path `
        -Arguments @("/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-")
}

function Ensure-VCRuntime {
    $vcKey = "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64"
    if ((Test-Path $vcKey) -and ((Get-ItemProperty $vcKey).Installed -eq 1)) {
        Write-Log "Visual C++ Runtime is already installed"
        return
    }
    $path = Join-Path $DownloadRoot "vc_redist.x64.exe"
    Install-FromUrl `
        -Name "Visual C++ Runtime" `
        -Url "https://aka.ms/vs/17/release/vc_redist.x64.exe" `
        -InstallerPath $path `
        -Arguments @("/install", "/quiet", "/norestart")
}

function Ensure-DockerDesktop {
    $dockerDesktop = "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe"
    if ((Test-CommandExists "docker") -and (Test-Path $dockerDesktop)) {
        Write-Log "Docker Desktop is already installed"
    } else {
        $path = Join-Path $DownloadRoot "DockerDesktopInstaller.exe"
        Install-FromUrl `
            -Name "Docker Desktop" `
            -Url "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe" `
            -InstallerPath $path `
            -Arguments @("install", "--quiet", "--accept-license")
    }

    try {
        docker info *> $null
        Write-Log "Docker is already running"
        return
    } catch {
        if (Test-Path $dockerDesktop) {
            Write-Log "Starting Docker Desktop"
            Start-Process -FilePath $dockerDesktop -WindowStyle Hidden
        }
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            docker info *> $null
            Write-Log "Docker is running"
            return
        } catch {
            Start-Sleep -Seconds 5
        }
    }
    throw "Docker did not become ready. A Windows reboot may be required, then run PMM Launcher.exe."
}

function Install-ProjectPayload {
    New-Item -ItemType Directory -Force -Path (Split-Path $InstallRoot -Parent) | Out-Null
    $payloadZip = Join-Path $PSScriptRoot "pmm-project.zip"
    if (Test-Path $payloadZip) {
        $staging = Join-Path $StateRoot "staging"
        if (Test-Path $staging) {
            Remove-Item -LiteralPath $staging -Recurse -Force
        }
        New-Item -ItemType Directory -Force -Path $staging | Out-Null
        Expand-Archive -LiteralPath $payloadZip -DestinationPath $staging -Force
        $payloadRoot = Join-Path $staging "AI-Meeting-Assistant"
        if (-not (Test-Path $payloadRoot)) {
            $payloadRoot = $staging
        }
        if (Test-Path $InstallRoot) {
            $backup = "$InstallRoot.backup-{0:yyyyMMddHHmmss}" -f (Get-Date)
            Move-Item -LiteralPath $InstallRoot -Destination $backup
            Write-Log "Backed up previous install to $backup"
        }
        Move-Item -LiteralPath $payloadRoot -Destination $InstallRoot
        Remove-Item -LiteralPath $staging -Recurse -Force
        return
    }

    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
    if (Test-Path (Join-Path $repoRoot "docker-compose.yml")) {
        Write-Log "Installing from local source tree"
        if (-not (Test-Path $InstallRoot)) {
            New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
        }
        robocopy $repoRoot $InstallRoot /MIR /XD .git .agents .codex /XF PMMInstaller.exe "PMM Launcher.exe" | Out-Null
        if ($LASTEXITCODE -gt 7) {
            throw "Project copy failed with robocopy exit code $LASTEXITCODE"
        }
        return
    }

    throw "No packaged project payload was found."
}

function Ensure-EnvFile {
    $envPath = Join-Path $InstallRoot "PMM\.env"
    if (Test-Path $envPath) {
        Write-Log "PMM .env already exists"
        return
    }
    $secretBytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Fill($secretBytes)
    $secret = ($secretBytes | ForEach-Object { $_.ToString("x2") }) -join ""
    @"
TEXT_MODEL_BASE_URL=http://ollama:11434/v1
TEXT_MODEL_API_KEY=ollama
TEXT_MODEL_NAME=$OllamaModel
ENABLE_STREAM_OPTIONS=false
LLM_REQUEST_TIMEOUT=600
TRANSCRIPTION_BASE_URL=http://whisper-asr:9000/v1
TRANSCRIPTION_CONNECTOR=asr_endpoint
TRANSCRIPTION_API_KEY=unused
TRANSCRIPTION_MODEL=tiny
ASR_DIARIZE=false
ASR_TIMEOUT=1800
SECRET_KEY=$secret
ALLOW_REGISTRATION=true
LOG_LEVEL=INFO
"@ | Set-Content -Path $envPath -Encoding UTF8
    Write-Log "Created PMM .env"
}

function Ensure-ProjectFolders {
    New-Item -ItemType Directory -Force `
        -Path (Join-Path $InstallRoot "PMM\uploads"), (Join-Path $InstallRoot "PMM\instance") `
        | Out-Null
    Write-Log "Required PMM runtime folders are present"
}

function Invoke-Compose {
    param([string[]]$Arguments)
    Push-Location $InstallRoot
    try {
        & docker compose @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "docker compose $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

function Ensure-OllamaModel {
    $models = docker exec ollama ollama list 2>$null
    if ($LASTEXITCODE -eq 0 -and ($models -match [regex]::Escape($OllamaModel))) {
        Write-Log "Ollama model $OllamaModel is already available"
        return
    }
    Write-Log "Pulling Ollama model $OllamaModel"
    docker exec ollama ollama pull $OllamaModel
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to pull Ollama model $OllamaModel"
    }
}

function Wait-ContainerRunning {
    param([string]$ContainerName)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $status = docker inspect -f "{{.State.Running}}" $ContainerName 2>$null
        if ($LASTEXITCODE -eq 0 -and $status.Trim() -eq "true") {
            Write-Log "$ContainerName container is running"
            return
        }
        Start-Sleep -Seconds 5
    }
    throw "$ContainerName container did not start within $TimeoutSeconds seconds."
}

function Wait-HttpReady {
    param([string]$Name, [string]$Url)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 10
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                Write-Log "$Name is reachable at $Url"
                return
            }
        } catch {
            Start-Sleep -Seconds 5
        }
    }
    throw "$Name did not become reachable at $Url within $TimeoutSeconds seconds."
}

try {
    if (-not (Test-Admin)) {
        throw "PMM Installer.exe must be run as Administrator so it can install Docker Desktop, WSL2, Git, and Windows runtimes."
    }

    Ensure-Wsl2
    Ensure-Git
    Ensure-VCRuntime
    Ensure-DockerDesktop
    Install-ProjectPayload
    Ensure-ProjectFolders
    Ensure-EnvFile
    Invoke-Compose @("pull")
    Invoke-Compose @("build")
    Invoke-Compose @("up", "-d")
    Wait-ContainerRunning "pmm"
    Wait-ContainerRunning "whisper-asr"
    Wait-ContainerRunning "ollama"
    Ensure-OllamaModel
    Wait-HttpReady "PMM" $AppUrl
    Start-Process $AppUrl
    Write-Log "PMM installation completed successfully"
} catch {
    Write-Log $_.Exception.Message "ERROR"
    throw
} finally {
    Stop-Transcript | Out-Null
}
