param(
    [string]$JenkinsHome = (Join-Path (Split-Path -Parent $PSScriptRoot) ".jenkins"),
    [string]$ProfilePath = (Join-Path $PSScriptRoot "../../config/release-job-profiles.json"),
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

function Convert-XmlForPowerShell {
    param([string]$Content)
    return $Content -replace '^\s*<\?xml version=[''\"]1\.1[''\"]', "<?xml version='1.0'"
}

function Get-RequiredValue {
    param([object]$Object, [string]$PropertyName, [string]$Context)
    $value = [string]$Object.$PropertyName
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "$Context is missing '$PropertyName'."
    }
    return $value.Trim()
}

function Get-ObjectPropertyMap {
    param([object]$Object)
    $result = @{}
    if ($null -ne $Object) {
        foreach ($property in $Object.PSObject.Properties) {
            $result[$property.Name] = $property.Value
        }
    }
    return $result
}

function ConvertTo-BooleanText {
    param([object]$Value, [string]$ParameterName)

    if ($Value -is [bool]) {
        return $Value.ToString().ToLowerInvariant()
    }
    if ($Value -is [string] -and $Value -match '^(?i:true|false)$') {
        return $Value.ToLowerInvariant()
    }
    throw "Boolean parameter '$ParameterName' must use true or false."
}

function Get-ChildElement {
    param([System.Xml.XmlDocument]$Document, [System.Xml.XmlElement]$Parent, [string]$Name)
    $child = $Parent.SelectSingleNode($Name)
    if ($null -eq $child) {
        $child = $Document.CreateElement($Name)
        [void]$Parent.AppendChild($child)
    }
    return [System.Xml.XmlElement]$child
}

function New-ParameterDefinitionsProperty {
    param(
        [object[]]$Parameters,
        [hashtable]$Defaults,
        [string]$AgentLabel
    )

    $document = New-Object System.Xml.XmlDocument
    $property = $document.CreateElement("hudson.model.ParametersDefinitionProperty")
    $definitions = $document.CreateElement("parameterDefinitions")
    [void]$property.AppendChild($definitions)

    foreach ($parameter in $Parameters) {
        $name = Get-RequiredValue -Object $parameter -PropertyName "name" -Context "Parameter definition"
        $type = Get-RequiredValue -Object $parameter -PropertyName "type" -Context "Parameter '$name'"
        if ($name -notmatch '^[A-Za-z][A-Za-z0-9_]*$') {
            throw "Parameter '$name' must use letters, numbers, and underscores only."
        }
        $description = [string]$parameter.description
        $defaultValue = if ($Defaults.ContainsKey($name)) { $Defaults[$name] } else { $parameter.default }

        # [AI] Agent display is derived from the fixed Job label, never from a user-supplied default.
        if ($type -eq "agentLabel") {
            $type = "choice"
            $defaultValue = $AgentLabel
            $parameterChoices = @($AgentLabel)
        }
        else {
            $parameterChoices = @($parameter.choices)
        }

        switch ($type) {
            "string" {
                $definition = $document.CreateElement("hudson.model.StringParameterDefinition")
                $trim = $document.CreateElement("trim")
                $trim.InnerText = "true"
                [void]$definition.AppendChild($trim)
            }
            "boolean" {
                $definition = $document.CreateElement("hudson.model.BooleanParameterDefinition")
            }
            "choice" {
                if ($parameterChoices.Count -eq 0) {
                    throw "Choice parameter '$name' has no choices."
                }
                if ($parameterChoices -notcontains [string]$defaultValue) {
                    throw "Default '$defaultValue' is not a valid choice for '$name'."
                }
                $definition = $document.CreateElement("hudson.model.ChoiceParameterDefinition")
            }
            default {
                throw "Parameter '$name' has unsupported type '$type'."
            }
        }

        $nameNode = $document.CreateElement("name")
        $nameNode.InnerText = $name
        [void]$definition.AppendChild($nameNode)
        $descriptionNode = $document.CreateElement("description")
        $descriptionNode.InnerText = $description
        [void]$definition.AppendChild($descriptionNode)

        if ($type -eq "choice") {
            $choicesNode = $document.CreateElement("choices")
            [void]$choicesNode.SetAttribute("class", "java.util.Arrays`$ArrayList")
            $arrayNode = $document.CreateElement("a")
            [void]$arrayNode.SetAttribute("class", "string-array")
            # [AI] Jenkins uses the first Choice value as its default, so place the resolved default first.
            $orderedChoices = @([string]$defaultValue) + @($parameterChoices | Where-Object { $_ -ne [string]$defaultValue })
            foreach ($choice in $orderedChoices) {
                $choiceNode = $document.CreateElement("string")
                $choiceNode.InnerText = [string]$choice
                [void]$arrayNode.AppendChild($choiceNode)
            }
            [void]$choicesNode.AppendChild($arrayNode)
            [void]$definition.AppendChild($choicesNode)
        }
        else {
            $defaultNode = $document.CreateElement("defaultValue")
            $defaultNode.InnerText = if ($type -eq "boolean") { ConvertTo-BooleanText -Value $defaultValue -ParameterName $name } else { [string]$defaultValue }
            [void]$definition.AppendChild($defaultNode)
        }

        [void]$definitions.AppendChild($definition)
    }
    return $property
}

function Merge-ReleaseJobConfig {
    param(
        [string]$GeneratedXml,
        [string]$ExistingPath
    )

    $existingDocument = [xml](Convert-XmlForPowerShell -Content (Get-Content -LiteralPath $ExistingPath -Raw -Encoding UTF8))
    $generatedDocument = [xml](Convert-XmlForPowerShell -Content $GeneratedXml)
    $existingRoot = $existingDocument.DocumentElement
    $generatedRoot = $generatedDocument.DocumentElement

    foreach ($nodeName in @("description", "definition", "assignedNode", "canRoam", "disabled")) {
        $generatedNode = $generatedRoot.SelectSingleNode($nodeName)
        $existingNode = $existingRoot.SelectSingleNode($nodeName)
        if ($generatedNode) {
            $importedNode = $existingDocument.ImportNode($generatedNode, $true)
            if ($existingNode) {
                [void]$existingRoot.ReplaceChild($importedNode, $existingNode)
            }
            else {
                [void]$existingRoot.AppendChild($importedNode)
            }
        }
    }

    $existingProperties = Get-ChildElement -Document $existingDocument -Parent $existingRoot -Name "properties"
    $existingParameterProperty = $existingProperties.SelectSingleNode("hudson.model.ParametersDefinitionProperty")
    $generatedParameterProperty = $generatedRoot.SelectSingleNode("properties/hudson.model.ParametersDefinitionProperty")
    if ($null -eq $existingParameterProperty) {
        # [AI] A missing parameter property is initialized once; later UI values are never replaced.
        [void]$existingProperties.AppendChild($existingDocument.ImportNode($generatedParameterProperty, $true))
    }
    else {
        $existingDefinitions = $existingParameterProperty.SelectSingleNode("parameterDefinitions")
        $generatedDefinitions = $generatedParameterProperty.SelectSingleNode("parameterDefinitions")
        foreach ($generatedDefinition in @($generatedDefinitions.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element })) {
            $parameterName = $generatedDefinition.SelectSingleNode("name").InnerText
            if ($null -eq $existingDefinitions.SelectSingleNode("*[name='$parameterName']")) {
                # [AI] Add newly introduced parameters without replacing any existing Job defaults.
                [void]$existingDefinitions.AppendChild($existingDocument.ImportNode($generatedDefinition, $true))
            }
        }
    }

    return "<?xml version='1.0' encoding='UTF-8'?>`r`n$($existingRoot.OuterXml)"
}

if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
    throw "Release Job profile configuration was not found: $ProfilePath. Copy config/release-job-profiles.example.json first."
}

$config = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
$parameters = @($config.parameters)
if ($parameters.Count -eq 0) {
    throw "Release Job profile configuration has no parameter definitions."
}

$parameterNames = @($parameters | ForEach-Object { [string]$_.name })
foreach ($job in @($config.jobs)) {
    $name = Get-RequiredValue -Object $job -PropertyName "name" -Context "Release Job"
    $repositoryUrl = Get-RequiredValue -Object $job -PropertyName "repositoryUrl" -Context "Release Job '$name'"
    $credentialsId = Get-RequiredValue -Object $job -PropertyName "credentialsId" -Context "Release Job '$name'"
    $scriptPath = Get-RequiredValue -Object $job -PropertyName "scriptPath" -Context "Release Job '$name'"
    $agentLabel = Get-RequiredValue -Object $job -PropertyName "agentLabel" -Context "Release Job '$name'"
    $environmentName = Get-RequiredValue -Object $job -PropertyName "environment" -Context "Release Job '$name'"

    if ($name -notmatch '^[A-Za-z0-9_.-]+$') {
        throw "Invalid Job name '$name'. Use letters, numbers, '.', '_' or '-'."
    }
    if ([System.IO.Path]::IsPathRooted($scriptPath) -or ($scriptPath -split '[/\\]') -contains '..') {
        throw "Release Job '$name' scriptPath must stay inside the SCM workspace."
    }
    $profile = $config.profiles.$environmentName
    if ($null -eq $profile) {
        throw "Release Job '$name' references unknown environment '$environmentName'."
    }

    $jobOverrides = Get-ObjectPropertyMap -Object $job.parameterOverrides
    # [AI] JSON omits optional arrays as $null; do not treat that as one required empty override.
    $requiredJobOverrides = if ($null -eq $profile.requiredJobOverrides) { @() } else { @($profile.requiredJobOverrides) }
    foreach ($requiredOverride in $requiredJobOverrides) {
        if (-not $jobOverrides.ContainsKey([string]$requiredOverride) -or [string]::IsNullOrWhiteSpace([string]$jobOverrides[[string]$requiredOverride])) {
            throw "Release Job '$name' environment '$environmentName' requires parameterOverrides.$requiredOverride."
        }
    }

    $defaults = @{}
    foreach ($parameter in $parameters) {
        if ($parameter.type -ne "agentLabel") {
            $defaults[[string]$parameter.name] = $parameter.default
        }
    }
    foreach ($entry in (Get-ObjectPropertyMap -Object $profile.defaults).GetEnumerator()) {
        if ($parameterNames -notcontains $entry.Key) {
            throw "Environment '$environmentName' overrides unknown parameter '$($entry.Key)'."
        }
        $defaults[$entry.Key] = $entry.Value
    }
    foreach ($entry in $jobOverrides.GetEnumerator()) {
        if ($parameterNames -notcontains $entry.Key) {
            throw "Release Job '$name' overrides unknown parameter '$($entry.Key)'."
        }
        $defaults[$entry.Key] = $entry.Value
    }

    $parameterProperty = New-ParameterDefinitionsProperty -Parameters $parameters -Defaults $defaults -AgentLabel $agentLabel
    $parameterXml = $parameterProperty.OuterXml
    $xml = @"
<?xml version='1.0' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <actions/>
  <description>SCM managed by jenkins-infra. Release parameters are initialized for new Jobs; existing Jenkins UI values are preserved.</description>
  <keepDependencies>false</keepDependencies>
  <properties>$parameterXml</properties>
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
  <assignedNode>$(Escape-Xml $agentLabel)</assignedNode>
  <canRoam>false</canRoam>
  <disabled>false</disabled>
</flow-definition>
"@

    $jobPath = Join-Path $JenkinsHome "jobs/$name"
    $configPathOut = Join-Path $jobPath "config.xml"
    if ($DryRun) {
        $mode = if (Test-Path -LiteralPath $configPathOut -PathType Leaf) { "merge existing parameters" } else { "initialize all parameters" }
        Write-Host "[DryRun] $name ($environmentName) => $configPathOut ($mode)"
        continue
    }

    New-Item -ItemType Directory -Force -Path $jobPath | Out-Null
    $configToWrite = if (Test-Path -LiteralPath $configPathOut -PathType Leaf) {
        Merge-ReleaseJobConfig -GeneratedXml $xml -ExistingPath $configPathOut
    }
    else {
        $xml
    }
    Set-Content -LiteralPath $configPathOut -Value $configToWrite -Encoding UTF8
    Write-Host "Provisioned Release Job '$name' for '$environmentName'. Existing Jenkins UI parameter values were preserved."
}

if (@($config.jobs).Count -eq 0) {
    Write-Host "No Release Jobs configured in $ProfilePath. Add jobs after copying the example configuration."
}
