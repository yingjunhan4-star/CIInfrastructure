param(
    [string]$JenkinsHome = (Join-Path $env:USERPROFILE ".jenkins-infra")
)

$ErrorActionPreference = "Stop"
$pidPath = Join-Path $JenkinsHome "jenkins.pid"
if (-not (Test-Path -LiteralPath $pidPath -PathType Leaf)) {
    Write-Host "No Jenkins PID file found: $pidPath"
    exit 0
}

$processId = [int](Get-Content -LiteralPath $pidPath -Raw).Trim()
$processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction SilentlyContinue
if ($processInfo) {
    $commandLine = if ($null -ne $processInfo.CommandLine) { $processInfo.CommandLine } else { "" }
    if (-not $commandLine.Contains($JenkinsHome)) {
        throw "PID $processId does not belong to JenkinsHome $JenkinsHome. Refusing to stop it."
    }
    Stop-Process -Id $processId -ErrorAction Stop
    Write-Host "Stopped Jenkins. PID=$processId"
}
else {
    Write-Host "Jenkins process is not running. PID=$processId"
}

Remove-Item -LiteralPath $pidPath -Force
