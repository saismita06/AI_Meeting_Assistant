param(
    [string]$InstallRoot = "$env:ProgramData\PMM\AI-Meeting-Assistant",
    [string]$AppUrl = "http://localhost:8899",
    [int]$TimeoutSeconds = 600
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$StateRoot = "$env:ProgramData\PMM"
$LogRoot = Join-Path $StateRoot "Logs"
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$LogFile = Join-Path $LogRoot ("launcher-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
Start-Transcript -Path $LogFile -Append | Out-Null

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    Write-Host ("[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message)
}

function Test-CommandExists {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Start-DockerDesktop {
    if (-not (Test-CommandExists "docker")) {
        throw "Docker CLI was not found. Run PMM Installer.exe first."
    }

    $dockerDesktop = "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe"
    try {
        docker info *> $null
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
    throw "Docker did not become ready within $TimeoutSeconds seconds."
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

try {
    if (-not (Test-Path (Join-Path $InstallRoot "docker-compose.yml"))) {
        throw "PMM install was not found at $InstallRoot. Run PMM Installer.exe first."
    }

    Start-DockerDesktop
    Invoke-Compose @("up", "-d")
    Wait-ContainerRunning "pmm"
    Wait-ContainerRunning "whisper-asr"
    Wait-ContainerRunning "ollama"
    Wait-HttpReady "PMM" $AppUrl
    Start-Process $AppUrl
    Write-Log "PMM is ready"
} catch {
    Write-Log $_.Exception.Message "ERROR"
    throw
} finally {
    Stop-Transcript | Out-Null
}
