param()
$ErrorActionPreference = 'Stop'
function Find-Command([string]$Name) { $command = Get-Command $Name -ErrorAction SilentlyContinue; if ($command) { $command.Source } }
function Java-Major([string]$Path) { if (!$Path) { return 0 }; $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; try { $line = (& $Path -version 2>&1 | Select-Object -First 1).ToString() } finally { $ErrorActionPreference = $previous }; if ($line -match '"([0-9]+)(?:\.([0-9]+))?') { if ($Matches[1] -eq '1') { return [int]$Matches[2] }; return [int]$Matches[1] }; 0 }
$missing = @(); $remediation = @{}; $java = Find-Command java; $javaMajor = Java-Major $java
Write-Host 'Windows CIInfrastructure Controller prerequisites:'
if ($java -and $javaMajor -ge 17) { Write-Host "[OK] Java $javaMajor`: $java" } else { Write-Host "[MISSING] Java 17"; $missing += 'Java 17'; $remediation['Java 17'] = 'Java' }
Write-Host 'Windows Jenkins node runtime contract:'
foreach ($name in 'pwsh','python','svn') { $path = Find-Command $name; if ($path) { Write-Host "[OK] $name`: $path" } else { Write-Host "[MISSING] $name"; $missing += $name; $remediation[$name] = @{pwsh='PowerShell';python='Python';svn='Svn'}[$name] } }
if ($missing.Count) { foreach ($item in $missing) { $option = $remediation[$item]; Write-Host "  Next: .\install_prerequisites.ps1 -$option -WhatIf"; Write-Host "  Install: .\install_prerequisites.ps1 -$option" }; Write-Host "Restart the Jenkins process after installation so its PATH is refreshed."; exit 1 }
