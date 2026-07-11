param(
    [string]$JenkinsHome = (Join-Path (Split-Path -Parent $PSScriptRoot) ".jenkins"),
    [string]$JenkinsWar = "",
    [string]$JenkinsVersion = "2.541.3",
    [ValidateRange(1, 65535)]
    [int]$Port = 8080,
    [string]$ListenAddress = "127.0.0.1",
    [switch]$SkipPluginInstall
)

$ErrorActionPreference = "Stop"

function Test-IsWindows {
    return $env:OS -eq "Windows_NT"
}

function Download-File {
    param([string]$Url, [string]$OutFile)

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutFile) | Out-Null
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $OutFile
}

function Get-PluginManagerUrl {
    $fallback = "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.15.0/jenkins-plugin-manager-2.15.0.jar"
    try {
        $release = Invoke-RestMethod `
            -Headers @{ "User-Agent" = "CIInfrastructure" } `
            -Uri "https://api.github.com/repos/jenkinsci/plugin-installation-manager-tool/releases/latest"
        $asset = $release.assets | Where-Object {
            $_.name -like "jenkins-plugin-manager-*.jar" -and $_.name -notlike "*.sha256"
        } | Select-Object -First 1
        if ($asset.browser_download_url) {
            return $asset.browser_download_url
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

    New-Item -ItemType Directory -Force -Path $pluginsPath | Out-Null
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

    if (Test-IsWindows) {
        $connection = Get-NetTCPConnection -LocalPort $TcpPort -State Listen -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($connection) {
            return [int]$connection.OwningProcess
        }
        return 0
    }

    $lsof = Get-Command lsof -ErrorAction SilentlyContinue
    if (-not $lsof) {
        throw "lsof is required on macOS/Linux to inspect listening ports."
    }
    $pidText = & $lsof.Source -nP -iTCP:$TcpPort -sTCP:LISTEN -t 2>$null |
        Select-Object -First 1
    if ($pidText -and $pidText.ToString().Trim() -match '^[0-9]+$') {
        return [int]$pidText
    }
    return 0
}

function Get-ProcessCommandLine {
    param([int]$ProcessId)

    if (Test-IsWindows) {
        $info = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
        if ($info -and $info.CommandLine) {
            return $info.CommandLine
        }
        return ""
    }

    $psCommand = Get-Command ps -ErrorAction Stop
    return ((& $psCommand.Source -p $ProcessId -o command= 2>$null) -join " ").Trim()
}

function Test-ManagedProcess {
    param([int]$ProcessId, [string]$HomePath, [string]$WarPath)

    $commandLine = Get-ProcessCommandLine -ProcessId $ProcessId
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
    throw "Jenkins did not become ready on port $TcpPort. Check $(Join-Path $JenkinsHome 'logs/jenkins.err.log')."
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
$startParameters = @{
    FilePath = $java
    ArgumentList = $arguments
    WorkingDirectory = $JenkinsHome
    RedirectStandardOutput = $stdout
    RedirectStandardError = $stderr
    PassThru = $true
}
if (Test-IsWindows) {
    $startParameters.WindowStyle = "Hidden"
}

# Jenkins reads JENKINS_HOME from the child process environment.
$env:JENKINS_HOME = $JenkinsHome
$process = Start-Process @startParameters
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
