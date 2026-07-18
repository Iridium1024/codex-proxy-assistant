param(
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
$standaloneGenerator = Join-Path $projectRoot 'scripts\generate_standalone_cmd.ps1'
$sourceInputFiles = [ordered]@{
    'run_gui.py' = (Join-Path $projectRoot 'run_gui.py')
    'src/codex_proxy_assistant/main.py' = (Join-Path $projectRoot 'src\codex_proxy_assistant\main.py')
    'src/codex_proxy_assistant/main_window.py' = (Join-Path $projectRoot 'src\codex_proxy_assistant\main_window.py')
    'src/codex_proxy_assistant/theme.py' = (Join-Path $projectRoot 'src\codex_proxy_assistant\theme.py')
    'src/codex_proxy_assistant/backend.py' = (Join-Path $projectRoot 'src\codex_proxy_assistant\backend.py')
    'src/codex_proxy_assistant/workers.py' = (Join-Path $projectRoot 'src\codex_proxy_assistant\workers.py')
    'powershell/CodexProxy.Cli.ps1' = (Join-Path $projectRoot 'powershell\CodexProxy.Cli.ps1')
    'powershell/CodexProxy.Core.psm1' = (Join-Path $projectRoot 'powershell\CodexProxy.Core.psm1')
}
$sourceInputHashes = [ordered]@{}
foreach ($entry in $sourceInputFiles.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
        throw ("Required build input is missing: {0}" -f $entry.Key)
    }
    $sourceInputHashes[$entry.Key] = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash
}

if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    throw 'Run scripts\setup_env.ps1 before building.'
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $standaloneGenerator -Check
if ($LASTEXITCODE -ne 0) { throw 'The generated standalone CMD is stale.' }

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
    --add-data ((Join-Path $projectRoot 'powershell\CodexProxy.Cli.ps1') + ';powershell') `
    --add-data ((Join-Path $projectRoot 'powershell\CodexProxy.Core.psm1') + ';powershell') `
    --add-data ((Join-Path $projectRoot 'assets') + ';assets') `
    --version-file (Join-Path $projectRoot 'packaging\version_info.txt') `
    --distpath $releaseRoot `
    --workpath (Join-Path $workRoot 'pyinstaller') `
    --specpath $workRoot `
    (Join-Path $projectRoot 'run_gui.py')
if ($LASTEXITCODE -ne 0) { throw 'PyInstaller packaging failed.' }

foreach ($entry in $sourceInputFiles.GetEnumerator()) {
    $currentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash
    if ($currentHash -ne $sourceInputHashes[$entry.Key]) {
        throw ("Build input changed while PyInstaller was running; rebuild required: {0}" -f $entry.Key)
    }
}

$packageRoot = Join-Path $releaseRoot 'CodexProxyAssistant'
Copy-Item -LiteralPath $originalCmd -Destination (Join-Path $packageRoot 'codex-vpn-repair.cmd')
Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md') -Destination (Join-Path $packageRoot 'README.md')

$exe = Join-Path $packageRoot 'CodexProxyAssistant.exe'
$gitCommit = $null
$gitDirty = $null
try {
    $gitCommit = (& git -C $projectRoot rev-parse HEAD 2>$null | Select-Object -First 1).Trim()
    $gitDirty = [bool](@(& git -C $projectRoot status --porcelain 2>$null).Count -gt 0)
} catch { }
$manifest = [ordered]@{
    application_version = '0.1.3'
    built_at_local = [DateTimeOffset]::Now.ToString('o')
    source = [ordered]@{
        git_commit = $gitCommit
        git_dirty = $gitDirty
        inputs = $sourceInputHashes
    }
    runtime = [ordered]@{
        python = (& $python --version 2>&1 | Select-Object -First 1)
        pyinstaller = (& $python -m PyInstaller --version 2>&1 | Select-Object -First 1)
    }
    executable = [ordered]@{
        name = 'CodexProxyAssistant.exe'
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash
    }
    fallback_cmd = [ordered]@{
        name = 'codex-vpn-repair.cmd'
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $packageRoot 'codex-vpn-repair.cmd')).Hash
        generated_from_core = $true
        core_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $projectRoot 'powershell\CodexProxy.Core.psm1')).Hash
        entrypoint_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $projectRoot 'powershell\CodexProxy.Standalone.ps1')).Hash
    }
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $releaseRoot 'build-manifest.json') -Encoding UTF8

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
