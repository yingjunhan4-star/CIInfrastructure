param(
    [ValidateRange(1, 65535)]
    [int]$Port = 8080,
    [string]$ListenAddress = "127.0.0.1"
)

$ErrorActionPreference = "Stop"
$url = "http://$ListenAddress`:$Port/api/json"
try {
    $jenkins = Invoke-RestMethod -Uri $url -TimeoutSec 5
    Write-Host "Jenkins is healthy. URL=http://$ListenAddress`:$Port/"
    Write-Host "Version=$($jenkins.mode) Jobs=$(@($jenkins.jobs).Count)"
}
catch {
    Write-Error "Jenkins health check failed: $url`n$($_.Exception.Message)"
    exit 1
}
