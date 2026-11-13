@echo off
where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo PowerShell 7 is required.
  pause
  exit /b 1
)
pwsh.exe -NoProfile -STA -File "%~dp0Repair-Tou.ps1"
if errorlevel 1 pause
