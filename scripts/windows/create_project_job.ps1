[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$TemplatePath,
    [string]$JenkinsHome = '',
    [string]$JobName = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
# [AI] PowerShell resolves parameter defaults before $PSScriptRoot is reliable.
if ([string]::IsNullOrWhiteSpace($JenkinsHome)) {
    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $JenkinsHome = Join-Path (Split-Path -Parent $scriptDirectory) '.jenkins'
}
function Escape-Xml([string]$Value) { [System.Security.SecurityElement]::Escape($(if ($null -eq $Value) { '' } else { $Value })) }
function Require($Value, [string]$Name) { if ([string]::IsNullOrWhiteSpace([string]$Value)) { throw "$Name is required." }; [string]$Value }

$template = Get-Content -LiteralPath $TemplatePath -Raw | ConvertFrom-Json
$name = if ($JobName) { $JobName } else { Require $template.jobName 'jobName' }
if ($name -notmatch '^[A-Za-z0-9_.-]+$') { throw "Invalid Job name: $name" }
$scm = $template.scm
$remote = Escape-Xml (Require $scm.repositoryUrl 'scm.repositoryUrl')
$credentials = Escape-Xml (Require $scm.credentialsId 'scm.credentialsId')
$scriptPath = Escape-Xml (Require $scm.scriptPath 'scm.scriptPath')
if ([IO.Path]::IsPathRooted($scm.scriptPath) -or ($scm.scriptPath -split '[/\\]') -contains '..') { throw 'scm.scriptPath must stay inside the SCM workspace.' }

$seen = @{}; $parameters = [Text.StringBuilder]::new()
foreach ($parameter in @($template.parameters)) {
    $parameterName = Require $parameter.name 'parameter.name'
    if ($seen[$parameterName]) { throw "Duplicate parameter: $parameterName" }; $seen[$parameterName] = $true
    $parameterDescription = Escape-Xml ([string]$parameter.description); $escapedName = Escape-Xml $parameterName
    switch ([string]$parameter.type) {
        'boolean' { [void]$parameters.AppendLine("<hudson.model.BooleanParameterDefinition><name>$escapedName</name><description>$parameterDescription</description><defaultValue>$([bool]$parameter.defaultValue -as [string]).ToLower()</defaultValue></hudson.model.BooleanParameterDefinition>") }
        'string' { [void]$parameters.AppendLine("<hudson.model.StringParameterDefinition><name>$escapedName</name><description>$parameterDescription</description><defaultValue>$(Escape-Xml ([string]$parameter.defaultValue))</defaultValue><trim>true</trim></hudson.model.StringParameterDefinition>") }
        'choice' { $choices = @($parameter.choices); if (!$choices) { throw "Choice parameter $parameterName has no choices." }; [void]$parameters.Append("<hudson.model.ChoiceParameterDefinition><name>$escapedName</name><description>$parameterDescription</description><choices class=`"java.util.Arrays`$ArrayList`"><a class=`"string-array`">"); foreach ($choice in $choices) { [void]$parameters.Append("<string>$(Escape-Xml ([string]$choice))</string>") }; [void]$parameters.AppendLine('</a></choices></hudson.model.ChoiceParameterDefinition>') }
        default { throw "Unsupported parameter type: $($parameter.type)" }
    }
}

$xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<flow-definition plugin="workflow-job"><actions/><description>Created once by CIInfrastructure from a project template. Jenkins UI owns parameters after creation.</description><keepDependencies>false</keepDependencies><properties><hudson.model.ParametersDefinitionProperty><parameterDefinitions>$parameters</parameterDefinitions></hudson.model.ParametersDefinitionProperty></properties><definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps"><scm class="hudson.scm.SubversionSCM" plugin="subversion"><locations><hudson.scm.SubversionSCM_-ModuleLocation><remote>$remote</remote><credentialsId>$credentials</credentialsId><local>.</local><depthOption>infinity</depthOption><ignoreExternalsOption>false</ignoreExternalsOption></hudson.scm.SubversionSCM_-ModuleLocation></locations><workspaceUpdater class="hudson.scm.subversion.UpdateUpdater"/></scm><scriptPath>$scriptPath</scriptPath><lightweight>false</lightweight></definition><triggers/><disabled>false</disabled></flow-definition>
"@
$jobPath = Join-Path $JenkinsHome "jobs/$name"
if (Test-Path -LiteralPath $jobPath) { throw "Job '$name' already exists. This tool never updates existing jobs." }
if ($DryRun) { Write-Host "[DryRun] Would create $jobPath from $TemplatePath"; exit 0 }
# [AI] CIInfrastructure creates only a new Job; the Jenkins UI owns it afterward.
New-Item -ItemType Directory -Path $jobPath -ErrorAction Stop | Out-Null
[IO.File]::WriteAllText((Join-Path $jobPath 'config.xml'), $xml, [Text.UTF8Encoding]::new($false))
Write-Host "Created Job '$name'. Restart Jenkins to load it."
