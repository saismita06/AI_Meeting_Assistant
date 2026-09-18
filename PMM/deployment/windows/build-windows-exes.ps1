param(
    [string]$OutputDir = (Join-Path (Resolve-Path ".").Path "dist\windows")
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir "..\..\..")
$PackageRoot = Join-Path $env:TEMP ("pmm-installer-build-{0:yyyyMMddHHmmss}" -f (Get-Date))
$PayloadRoot = Join-Path $PackageRoot "AI-Meeting-Assistant"
$PayloadZip = Join-Path $PackageRoot "pmm-project.zip"
New-Item -ItemType Directory -Force -Path $OutputDir, $PayloadRoot | Out-Null

function Invoke-IExpress {
    param(
        [string]$SedPath
    )
    $iexpress = Join-Path $env:SystemRoot "System32\iexpress.exe"
    if (-not (Test-Path $iexpress)) {
        throw "iexpress.exe was not found. Build on Windows with IExpress available."
    }
    $process = Start-Process -FilePath $iexpress -ArgumentList @("/N", "/Q", $SedPath) -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "IExpress failed for $SedPath with exit code $($process.ExitCode)"
    }
}

function New-SedFile {
    param(
        [string]$Path,
        [string]$PackageName,
        [string]$Command,
        [string[]]$Files
    )

    $sourceLines = New-Object System.Collections.Generic.List[string]
    $fileLines = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $Files.Count; $i++) {
        $fileName = Split-Path $Files[$i] -Leaf
        $sourceLines.Add("FILE$($i)=$fileName")
        $fileLines.Add("%FILE$($i)%=")
    }
    $sourceDir = Split-Path $Files[0] -Parent
    $sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$PackageName
FriendlyName=PMM
AppLaunched=$Command
PostInstallCmd=<None>
AdminQuietInstCmd=$Command
UserQuietInstCmd=$Command
SourceFiles=SourceFiles
[Strings]
"@
    $sed | Set-Content -Path $Path -Encoding ASCII
    $sourceLines | Add-Content -Path $Path -Encoding ASCII
    @"
[SourceFiles]
SourceFiles0=$sourceDir\
[SourceFiles0]
"@ | Add-Content -Path $Path -Encoding ASCII
    $fileLines | Add-Content -Path $Path -Encoding ASCII
}

try {
    robocopy $RepoRoot $PayloadRoot /MIR /XD .git .agents .codex dist uploads instance /XF "PMM Installer.exe" "PMM Launcher.exe" | Out-Null
    if ($LASTEXITCODE -gt 7) {
        throw "robocopy failed with exit code $LASTEXITCODE"
    }
    Compress-Archive -Path $PayloadRoot -DestinationPath $PayloadZip -Force

    Copy-Item (Join-Path $ScriptDir "PMMInstaller.ps1") (Join-Path $PackageRoot "PMMInstaller.ps1") -Force
    Copy-Item (Join-Path $ScriptDir "PMMLauncher.ps1") (Join-Path $PackageRoot "PMMLauncher.ps1") -Force

    $installerExe = Join-Path $OutputDir "PMM Installer.exe"
    $launcherExe = Join-Path $OutputDir "PMM Launcher.exe"
    $installerSed = Join-Path $PackageRoot "installer.sed"
    $launcherSed = Join-Path $PackageRoot "launcher.sed"

    New-SedFile `
        -Path $installerSed `
        -PackageName $installerExe `
        -Command "powershell.exe -NoProfile -ExecutionPolicy Bypass -File PMMInstaller.ps1" `
        -Files @((Join-Path $PackageRoot "PMMInstaller.ps1"), $PayloadZip)

    New-SedFile `
        -Path $launcherSed `
        -PackageName $launcherExe `
        -Command "powershell.exe -NoProfile -ExecutionPolicy Bypass -File PMMLauncher.ps1" `
        -Files @((Join-Path $PackageRoot "PMMLauncher.ps1"))

    Invoke-IExpress $installerSed
    Invoke-IExpress $launcherSed
    Write-Host "Created:"
    Write-Host "  $installerExe"
    Write-Host "  $launcherExe"
} finally {
    if (Test-Path $PackageRoot) {
        Remove-Item -LiteralPath $PackageRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
