param(
    [string]$JenkinsHome = (Join-Path (Split-Path -Parent $PSScriptRoot) ".jenkins"),
    [string]$ConfigPath = (Join-Path $PSScriptRoot "../../config/jobs.json"),
    [switch]$DryRun,
    [switch]$ResetJobConfig
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

function Convert-XmlForPowerShell {
    param([string]$Content)

    $xmlDeclarationPattern = '^\s*<\?xml version=[''\"]1\.1[''\"]'
    return $Content -replace $xmlDeclarationPattern, "<?xml version='1.0'"
}

function Merge-ExistingJobConfig {
    param(
        [string]$GeneratedXml,
        [string]$ExistingPath
    )

    try {
        $existingContent = Convert-XmlForPowerShell -Content (Get-Content -LiteralPath $ExistingPath -Raw -Encoding UTF8)
        $existingDocument = [xml]$existingContent
        $generatedDocument = [xml](Convert-XmlForPowerShell -Content $GeneratedXml)
        $generatedDefinition = $generatedDocument.DocumentElement.SelectSingleNode("definition")
        $existingDefinition = $existingDocument.DocumentElement.SelectSingleNode("definition")

        if ($null -eq $generatedDefinition) {
            throw "Generated Job config has no definition node."
        }

        $importedDefinition = $existingDocument.ImportNode($generatedDefinition, $true)
        if ($existingDefinition) {
            $existingDocument.DocumentElement.ReplaceChild($importedDefinition, $existingDefinition) | Out-Null
        }
        else {
            $existingDocument.DocumentElement.AppendChild($importedDefinition) | Out-Null
        }

        return "<?xml version='1.0' encoding='UTF-8'?>`r`n$($existingDocument.DocumentElement.OuterXml)"
    }
    catch {
        throw "Unable to preserve existing Jenkins Job config '$ExistingPath': $($_.Exception.Message)"
    }
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
  <description>SCM managed by jenkins-infra. Existing Job settings are preserved unless -ResetJobConfig is used.</description>
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
      <workspaceUpdater class="hudson.scm.subversion.UpdateWithRevertUpdater"/>
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
        if ((Test-Path -LiteralPath $configPathOut -PathType Leaf) -and -not $ResetJobConfig) {
            Write-Host "[DryRun] $name <= $repositoryUrl / $scriptPath (existing Job settings preserved)"
        }
        else {
            Write-Host "[DryRun] $name <= $repositoryUrl / $scriptPath"
        }
        continue
    }

    New-Item -ItemType Directory -Force -Path $jobPath | Out-Null
    $configToWrite = $xml
    if ((Test-Path -LiteralPath $configPathOut -PathType Leaf) -and -not $ResetJobConfig) {
        $configToWrite = Merge-ExistingJobConfig -GeneratedXml $xml -ExistingPath $configPathOut
        Write-Host "Updated Pipeline Job SCM while preserving existing settings: $name"
    }
    else {
        Write-Host "Created or reset Pipeline Job: $name"
    }
    Set-Content -LiteralPath $configPathOut -Value $configToWrite -Encoding UTF8
}

if ($jobs.Count -eq 0) {
    Write-Host "No jobs configured in $ConfigPath. Copy jobs.example.json and fill the actual SVN URLs first."
}
