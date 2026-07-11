param()

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

$javaPath = Get-CommandPath -Name "java"
$wingetPath = Get-CommandPath -Name "winget"
$javaMajor = Get-JavaMajorVersion -JavaPath $javaPath

Write-Host "Windows CIInfrastructure prerequisites:"
if ($javaPath -and $javaMajor -ge 17) {
    Write-Host "[OK] Java $javaMajor`: $javaPath"
}
else {
    Write-Host "[MISSING] Java 17 (found major version $javaMajor). Run install_prerequisites.bat or install_prerequisites.ps1 -Java."
}

if ($wingetPath) {
    Write-Host "[OK] winget: $wingetPath"
}
else {
    Write-Host "[INFO] winget is unavailable. Java must be installed manually."
}

if (-not $javaPath -or $javaMajor -lt 17) {
    exit 1
}
