param(
    [string]$JenkinsHome = $PSScriptRoot,
    [string]$JenkinsWar = ""
)

$ErrorActionPreference = "Stop"
$pidPath = Join-Path $JenkinsHome "jenkins.pid"
if (-not (Test-Path -LiteralPath $pidPath -PathType Leaf)) {
    Write-Host "No Jenkins PID file found: $pidPath"
    exit 0
}

if ([string]::IsNullOrWhiteSpace($JenkinsWar)) {
    $JenkinsWar = Get-ChildItem -LiteralPath $JenkinsHome -Filter "jenkins-*.war" -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}

$processId = [int](Get-Content -LiteralPath $pidPath -Raw).Trim()
$processInfo = Get-Process -Id $processId -ErrorAction SilentlyContinue
if ($processInfo) {
    if ($env:OS -eq "Windows_NT") {
        $cim = Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction SilentlyContinue
        $commandLine = if ($cim -and $cim.CommandLine) { $cim.CommandLine } else { "" }
    }
    else {
        $psCommand = Get-Command ps -ErrorAction Stop
        $commandLine = ((& $psCommand.Source -p $processId -o command= 2>$null) -join " ").Trim()
    }

    if ($JenkinsWar -and -not $commandLine.Contains($JenkinsHome) -and -not $commandLine.Contains($JenkinsWar)) {
        throw "PID $processId does not belong to JenkinsHome $JenkinsHome. Refusing to stop it."
    }
    Stop-Process -Id $processId -ErrorAction Stop
    Write-Host "Stopped Jenkins. PID=$processId"
}
else {
    Write-Host "Jenkins process is not running. PID=$processId"
}

Remove-Item -LiteralPath $pidPath -Force
