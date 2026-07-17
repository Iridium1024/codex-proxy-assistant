param(
    [switch]$SkipTests,
    [string]$ReleaseName = 'release',
    [switch]$CleanWorkspace
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$projectRoot = Split-Path -Parent $PSScriptRoot
$cacheRoot = $(if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [IO.Path]::GetTempPath() })
$python = Join-Path $cacheRoot 'CodexProxyAssistant\build-venv\Scripts\python.exe'
if ([string]::IsNullOrWhiteSpace($ReleaseName) -or [IO.Path]::GetFileName($ReleaseName) -ne $ReleaseName) {
    throw 'ReleaseName must be a single folder name inside the project.'
}
$releaseRoot = Join-Path $projectRoot $ReleaseName
$workRoot = Join-Path $projectRoot 'build'
$originalCmd = Join-Path $projectRoot 'codex-vpn-repair.cmd'
$expectedCmdHash = '1E3B964E07BF9FB231B64C7311F84A5F468BB2A934ED94FA2FD39E11F5780A5A'

if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    throw 'Run scripts\setup_env.ps1 before building.'
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $originalCmd).Hash -ne $expectedCmdHash) {
    throw 'The original codex-vpn-repair.cmd has changed; the build was stopped.'
}

if (-not $SkipTests) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'tests\test_core.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'PowerShell core tests failed.' }
    $env:QT_QPA_PLATFORM = 'offscreen'
    & $python -m unittest discover -s (Join-Path $projectRoot 'tests') -p 'test_*.py' -v
    if ($LASTEXITCODE -ne 0) { throw 'Python/GUI smoke tests failed.' }
}

$cleanTargets = @($releaseRoot, $workRoot)
if ($CleanWorkspace) {
    $cleanTargets += @(
        (Join-Path $projectRoot 'release-0.4.0'),
        (Join-Path $projectRoot 'release-preview')
    )
}

foreach ($target in $cleanTargets) {
    $fullTarget = [IO.Path]::GetFullPath($target)
    $fullProject = [IO.Path]::GetFullPath($projectRoot)
    if (-not $fullTarget.StartsWith($fullProject + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean a path outside the project: $fullTarget"
    }
    if (Test-Path -LiteralPath $fullTarget) { Remove-Item -LiteralPath $fullTarget -Recurse -Force }
}
[void](New-Item -ItemType Directory -Path $releaseRoot -Force)
[void](New-Item -ItemType Directory -Path $workRoot -Force)

& $python -m PyInstaller `
    --noconfirm `
    --clean `
    --windowed `
    --onedir `
    --name CodexProxyAssistant `
    --paths (Join-Path $projectRoot 'src') `
    --add-data ((Join-Path $projectRoot 'powershell') + ';powershell') `
    --add-data ((Join-Path $projectRoot 'assets') + ';assets') `
    --version-file (Join-Path $projectRoot 'packaging\version_info.txt') `
    --distpath $releaseRoot `
    --workpath (Join-Path $workRoot 'pyinstaller') `
    --specpath $workRoot `
    (Join-Path $projectRoot 'run_gui.py')
if ($LASTEXITCODE -ne 0) { throw 'PyInstaller packaging failed.' }

$packageRoot = Join-Path $releaseRoot 'CodexProxyAssistant'
Copy-Item -LiteralPath $originalCmd -Destination (Join-Path $packageRoot 'codex-vpn-repair.cmd')
Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md') -Destination (Join-Path $packageRoot 'README.md')

$exe = Join-Path $packageRoot 'CodexProxyAssistant.exe'
$manifest = [ordered]@{
    built_at_local = [DateTimeOffset]::Now.ToString('o')
    executable = [ordered]@{
        name = 'CodexProxyAssistant.exe'
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash
    }
    fallback_cmd = [ordered]@{
        name = 'codex-vpn-repair.cmd'
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $packageRoot 'codex-vpn-repair.cmd')).Hash
        original_preserved = $true
    }
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $packageRoot 'build-manifest.json') -Encoding UTF8

if ($CleanWorkspace) {
    if (Test-Path -LiteralPath $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
    }
    $pythonCaches = @(Get-ChildItem -LiteralPath $projectRoot -Directory -Recurse -Filter '__pycache__' -ErrorAction SilentlyContinue)
    foreach ($cache in $pythonCaches) {
        $fullCache = [IO.Path]::GetFullPath($cache.FullName)
        $fullProject = [IO.Path]::GetFullPath($projectRoot)
        if (-not $fullCache.StartsWith($fullProject + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean a cache outside the project: $fullCache"
        }
        Remove-Item -LiteralPath $fullCache -Recurse -Force
    }
}

Write-Host "Build complete: $exe"
Write-Host "EXE SHA-256: $($manifest.executable.sha256)"
Write-Host "CMD SHA-256: $($manifest.fallback_cmd.sha256)"
