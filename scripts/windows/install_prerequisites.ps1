param(
    [switch]$Java,
    [switch]$All,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

function Get-CommandPath {
    param([string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    return $null
}

function Get-JavaMajorVersion {
    param([string]$JavaPath)

    if (-not $JavaPath) {
        return 0
    }

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $versionLine = (& $JavaPath -version 2>&1 | Select-Object -First 1).ToString()
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($versionLine -notmatch '"([0-9]+)(?:\.([0-9]+))?') {
        return 0
    }

    $major = [int]$Matches[1]
    if ($major -eq 1 -and $Matches[2]) {
        return [int]$Matches[2]
    }
    return $major
}

function Ask-Install {
    param([string]$Name)

    $answer = Read-Host "Install $Name now? [y/N]"
    return $answer -match '^(y|yes)$'
}

$javaPath = Get-CommandPath -Name "java"
$javaMajor = Get-JavaMajorVersion -JavaPath $javaPath
$installJava = $All -or $Java
if (-not $installJava -and (-not $javaPath -or $javaMajor -lt 17)) {
    $installJava = Ask-Install -Name "Java 17"
}

if (-not $installJava) {
    Write-Host "No prerequisite selected for installation."
    exit 0
}

if ($javaPath -and $javaMajor -ge 17) {
    Write-Host "Java $javaMajor is already available: $javaPath"
    exit 0
}

$wingetPath = Get-CommandPath -Name "winget"
if (-not $wingetPath) {
    throw "winget is required to install Java automatically. Install Java 17 manually, then rerun the prerequisite check."
}

$arguments = @(
    "install",
    "--id", "EclipseAdoptium.Temurin.17.JDK",
    "--exact",
    "--accept-source-agreements",
    "--accept-package-agreements"
)

if ($WhatIf) {
    Write-Host "[WhatIf] winget $($arguments -join ' ')"
    exit 0
}

& $wingetPath @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Java 17 installation failed with exit code $LASTEXITCODE."
}

Write-Host "Java installation completed. Open a new terminal before running Jenkins."
