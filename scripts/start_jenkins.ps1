param(
    [string]$JenkinsHome = (Join-Path $env:USERPROFILE ".jenkins-infra"),
    [string]$JenkinsWar = "",
    [string]$JenkinsVersion = "2.541.3",
    [ValidateRange(1, 65535)]
    [int]$Port = 8080,
    [string]$ListenAddress = "127.0.0.1",
    [switch]$SkipPluginInstall
)

$ErrorActionPreference = "Stop"

function Download-File {
    param([string]$Url, [string]$OutFile)

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutFile) | Out-Null
    & curl.exe -L --fail --retry 3 --output $OutFile $Url
    if ($LASTEXITCODE -ne 0) {
        throw "Download failed: $Url"
    }
}

function Get-PluginManagerUrl {
    $fallback = "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.15.0/jenkins-plugin-manager-2.15.0.jar"
    try {
        $json = & curl.exe -L --fail -H "User-Agent: jenkins-infra" "https://api.github.com/repos/jenkinsci/plugin-installation-manager-tool/releases/latest" 2>$null
        if ($LASTEXITCODE -eq 0 -and $json) {
            $release = ($json -join "`n") | ConvertFrom-Json
            $asset = $release.assets | Where-Object {
                $_.name -like "jenkins-plugin-manager-*.jar" -and $_.name -notlike "*.sha256"
            } | Select-Object -First 1
            if ($asset.browser_download_url) {
                return $asset.browser_download_url
            }
        }
    }
    catch {
    }
    return $fallback
}

function Test-PluginInstalled {
    param([string]$PluginsPath, [string]$PluginName)

    return (Test-Path -LiteralPath (Join-Path $PluginsPath "$PluginName.jpi")) -or
        (Test-Path -LiteralPath (Join-Path $PluginsPath "$PluginName.hpi"))
}

function Ensure-PipelinePlugins {
    param([string]$HomePath, [string]$WarPath)

    $pluginsPath = Join-Path $HomePath "plugins"
    $required = @(
        "workflow-aggregator",
        "pipeline-stage-view",
        "subversion",
        "ssh-agent"
    )

    if (($required | Where-Object { -not (Test-PluginInstalled -PluginsPath $pluginsPath -PluginName $_) }).Count -eq 0) {
        return
    }

    $toolsPath = Join-Path $HomePath "tools"
    $managerPath = Join-Path $toolsPath "jenkins-plugin-manager.jar"
    if (-not (Test-Path -LiteralPath $managerPath -PathType Leaf)) {
        Download-File -Url (Get-PluginManagerUrl) -OutFile $managerPath
    }

    $pluginListPath = Join-Path $toolsPath "plugins.txt"
    $required | Set-Content -LiteralPath $pluginListPath -Encoding ASCII
    $java = (Get-Command java -ErrorAction Stop).Source
    & $java -jar $managerPath `
        --war $WarPath `
        --plugin-download-directory $pluginsPath `
        --plugin-file $pluginListPath

    if ($LASTEXITCODE -ne 0) {
        throw "Jenkins plugin installation failed."
    }
}

function Get-ListeningProcessId {
    param([int]$TcpPort)

    $connection = Get-NetTCPConnection -LocalPort $TcpPort -State Listen -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($connection) {
        return [int]$connection.OwningProcess
    }
    return 0
}

function Test-ManagedProcess {
    param([int]$ProcessId, [string]$HomePath, [string]$WarPath)

    $info = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
    if (-not $info) {
        return $false
    }
    $commandLine = if ($null -ne $info.CommandLine) { $info.CommandLine } else { "" }
    return $commandLine.Contains($HomePath) -or $commandLine.Contains($WarPath)
}

function Wait-ForJenkins {
    param([int]$TcpPort)

    $url = "http://127.0.0.1:$TcpPort/api/json"
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        try {
            Invoke-RestMethod -Uri $url -TimeoutSec 5 | Out-Null
            return
        }
        catch {
            Start-Sleep -Seconds 2
        }
    }
    throw "Jenkins did not become ready on port $TcpPort. Check $JenkinsHome\logs\jenkins.err.log."
}

if ([string]::IsNullOrWhiteSpace($JenkinsWar)) {
    $JenkinsWar = Join-Path $JenkinsHome "jenkins-$JenkinsVersion.war"
}

New-Item -ItemType Directory -Force -Path $JenkinsHome, (Join-Path $JenkinsHome "logs") | Out-Null
if (-not (Test-Path -LiteralPath $JenkinsWar -PathType Leaf)) {
    Download-File -Url "https://get.jenkins.io/war-stable/$JenkinsVersion/jenkins.war" -OutFile $JenkinsWar
}

if (-not $SkipPluginInstall) {
    Ensure-PipelinePlugins -HomePath $JenkinsHome -WarPath $JenkinsWar
}

$existingPid = Get-ListeningProcessId -TcpPort $Port
if ($existingPid -gt 0) {
    if (Test-ManagedProcess -ProcessId $existingPid -HomePath $JenkinsHome -WarPath $JenkinsWar) {
        Write-Host "Jenkins is already running. PID=$existingPid URL=http://$ListenAddress`:$Port/"
        exit 0
    }
    throw "Port $Port is already used by process $existingPid. Choose another port or stop that process."
}

$java = (Get-Command java -ErrorAction Stop).Source
$stdout = Join-Path $JenkinsHome "logs/jenkins.out.log"
$stderr = Join-Path $JenkinsHome "logs/jenkins.err.log"
$arguments = @(
    "-Djenkins.install.runSetupWizard=false",
    "-Dfile.encoding=UTF-8",
    "-Dsun.stdout.encoding=UTF-8",
    "-Dsun.stderr.encoding=UTF-8",
    "-jar", $JenkinsWar,
    "--httpPort=$Port",
    "--httpListenAddress=$ListenAddress"
)

$process = Start-Process -FilePath $java -ArgumentList $arguments -WorkingDirectory $JenkinsHome `
    -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
Set-Content -LiteralPath (Join-Path $JenkinsHome "jenkins.pid") -Value $process.Id -Encoding ASCII

try {
    Wait-ForJenkins -TcpPort $Port
}
catch {
    if (Test-Path -LiteralPath $stderr) {
        Write-Host (Get-Content -LiteralPath $stderr -Tail 30 -Raw)
    }
    throw
}

Write-Host "Started Jenkins. PID=$($process.Id)"
Write-Host "JENKINS_HOME=$JenkinsHome"
Write-Host "URL=http://$ListenAddress`:$Port/"
