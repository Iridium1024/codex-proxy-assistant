param(
    [switch]$UpgradePip
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$projectRoot = Split-Path -Parent $PSScriptRoot
$cacheRoot = $(if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [IO.Path]::GetTempPath() })
$venvRoot = Join-Path $cacheRoot 'CodexProxyAssistant\build-venv'
$python = Join-Path $venvRoot 'Scripts\python.exe'

if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    $launcher = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($launcher) {
        & $launcher.Source -3.11 -m venv $venvRoot
    } else {
        $systemPython = Get-Command python.exe -ErrorAction Stop
        & $systemPython.Source -m venv $venvRoot
    }
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create the Python virtual environment.' }
}

if ($UpgradePip) {
    & $python -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) { throw 'Failed to upgrade pip.' }
}

& $python -m pip install -r (Join-Path $projectRoot 'requirements-build.txt')
if ($LASTEXITCODE -ne 0) { throw 'Failed to install build dependencies.' }

& $python -c "import PyQt5, PyInstaller; print('Environment ready: PyQt5 + PyInstaller')"
if ($LASTEXITCODE -ne 0) { throw 'Failed to verify build dependencies.' }
Write-Host "Build environment: $venvRoot"
