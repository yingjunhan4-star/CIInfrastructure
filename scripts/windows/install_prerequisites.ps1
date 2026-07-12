param([switch]$Java,[switch]$PowerShell,[switch]$Python,[switch]$Svn,[switch]$All,[switch]$WhatIf)
$ErrorActionPreference = 'Stop'
function Has([string]$Name) { $null -ne (Get-Command $Name -ErrorAction SilentlyContinue) }
$winget = Get-Command winget -ErrorAction SilentlyContinue
if (!$winget) { throw 'winget is required for automatic installation.' }
$targets = @(); if ($All -or $Java) { if (!(Has java)) { $targets += @('EclipseAdoptium.Temurin.17.JDK','Java 17') } }; if ($All -or $PowerShell) { if (!(Has pwsh)) { $targets += @('Microsoft.PowerShell','PowerShell Core') } }; if ($All -or $Python) { if (!(Has python)) { $targets += @('Python.Python.3.13','Python 3.13') } }; if ($All -or $Svn) { if (!(Has svn)) { $targets += @('Slik.Subversion','Slik Subversion') } }
if (!$targets.Count) { Write-Host 'No supported prerequisite installation is required.'; exit 0 }
for ($index=0; $index -lt $targets.Count; $index+=2) { $args=@('install','--id',$targets[$index],'--exact','--accept-source-agreements','--accept-package-agreements'); if ($WhatIf) { Write-Host "[WhatIf] winget $($args -join ' ')" } else { & $winget.Source @args; if ($LASTEXITCODE -ne 0) { throw "Installation failed: $($targets[$index+1])" } } }
Write-Host 'Restart the Jenkins process after installation so it receives the updated PATH.'
