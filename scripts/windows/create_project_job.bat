@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%create_project_job.ps1" %*
