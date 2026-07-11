param(
    [string]$JenkinsHome = (Join-Path (Split-Path -Parent $PSScriptRoot) ".jenkins"),
    [string]$ConfigPath = (Join-Path $PSScriptRoot "../../config/jobs.json"),
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Escape-Xml {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) {
        return ""
    }
    return [System.Security.SecurityElement]::Escape($Value)
}

function Assert-JobValue {
    param([object]$Job, [string]$PropertyName)
    $value = [string]$Job.$PropertyName
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Job is missing '$PropertyName'."
    }
    return $value.Trim()
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Job configuration was not found: $ConfigPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$jobs = @($config.jobs)
foreach ($job in $jobs) {
    $name = Assert-JobValue -Job $job -PropertyName "name"
    $repositoryUrl = Assert-JobValue -Job $job -PropertyName "repositoryUrl"
    $credentialsId = Assert-JobValue -Job $job -PropertyName "credentialsId"
    $scriptPath = Assert-JobValue -Job $job -PropertyName "scriptPath"

    if ($name -notmatch '^[A-Za-z0-9_.-]+$') {
        throw "Invalid Job name '$name'. Use letters, numbers, '.', '_' or '-'."
    }
    if ([System.IO.Path]::IsPathRooted($scriptPath) -or ($scriptPath -split '[/\\]') -contains '..') {
        throw "Job '$name' scriptPath must stay inside the SCM workspace."
    }

    $xml = @"
<?xml version='1.0' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <actions/>
  <description>Managed by jenkins-infra. Do not edit generated config.xml manually.</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps">
    <scm class="hudson.scm.SubversionSCM" plugin="subversion">
      <locations>
        <hudson.scm.SubversionSCM_-ModuleLocation>
          <remote>$(Escape-Xml $repositoryUrl)</remote>
          <credentialsId>$(Escape-Xml $credentialsId)</credentialsId>
          <local>.</local>
          <depthOption>infinity</depthOption>
          <ignoreExternalsOption>true</ignoreExternalsOption>
        </hudson.scm.SubversionSCM_-ModuleLocation>
      </locations>
      <excludedRegions/>
      <excludedUsers/>
      <excludedCommitMessages/>
      <workspaceUpdater class="hudson.scm.subversion.UpdateWithCleanUpdater"/>
    </scm>
    <scriptPath>$(Escape-Xml $scriptPath)</scriptPath>
    <lightweight>true</lightweight>
  </definition>
  <disabled>false</disabled>
</flow-definition>
"@

    $jobPath = Join-Path $JenkinsHome "jobs/$name"
    $configPathOut = Join-Path $jobPath "config.xml"
    if ($DryRun) {
        Write-Host "[DryRun] Would write $configPathOut"
        Write-Host "[DryRun] $name <= $repositoryUrl / $scriptPath"
        continue
    }

    New-Item -ItemType Directory -Force -Path $jobPath | Out-Null
    Set-Content -LiteralPath $configPathOut -Value $xml -Encoding UTF8
    Write-Host "Created or updated Pipeline Job: $name"
}

if ($jobs.Count -eq 0) {
    Write-Host "No jobs configured in $ConfigPath. Copy jobs.example.json and fill the actual SVN URLs first."
}
