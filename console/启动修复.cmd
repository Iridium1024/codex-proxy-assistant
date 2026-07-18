@echo off
setlocal
chcp 65001 >nul
title Codex Proxy Assistant Console

set "SCRIPT_DIR=%~dp0"
set "ENTRY=%SCRIPT_DIR%CodexProxyAssistant.ps1"

if not exist "%ENTRY%" (
  echo [ERROR] CodexProxyAssistant.ps1 was not found.
  echo Extract the complete ZIP before running this launcher.
  echo.
  pause
  exit /b 2
)

where powershell.exe >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Windows PowerShell was not found.
  echo Windows PowerShell 5.1 is required.
  echo.
  pause
  exit /b 3
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ENTRY%" -Action menu
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
  echo.
  echo The program exited with code %EXIT_CODE%.
  pause
)
exit /b %EXIT_CODE%
