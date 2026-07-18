param(
    [string]$Version = '0.1.3',
    [switch]$KeepStage
)

$ErrorActionPreference = 'Stop'
$consoleRoot = Split-Path -Parent $PSScriptRoot
$projectRoot = Split-Path -Parent $consoleRoot
$artifactRoot = Join-Path $projectRoot 'artifacts'
$stageRoot = Join-Path $projectRoot 'release\console-package'
$zipName = "CodexProxyAssistant-Console-v$Version.zip"
$zipPath = Join-Path $artifactRoot $zipName

function Assert-WithinProject {
    param([string]$Path)
    $fullProject = [IO.Path]::GetFullPath($projectRoot).TrimEnd('\') + '\'
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith($fullProject, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean outside the project: $fullPath"
    }
}

foreach ($path in @($artifactRoot, $stageRoot, $zipPath)) { Assert-WithinProject $path }
if (Test-Path -LiteralPath $stageRoot) { Remove-Item -LiteralPath $stageRoot -Recurse -Force }
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
[void](New-Item -ItemType Directory -Path $artifactRoot -Force)
[void](New-Item -ItemType Directory -Path (Join-Path $stageRoot 'powershell') -Force)

$runtimeFiles = @(
    '启动修复.cmd',
    'CodexProxyAssistant.ps1',
    'README.txt',
    'README.md',
    'LICENSE',
    'VERSION'
)
foreach ($name in $runtimeFiles) {
    $source = if ($name -eq 'LICENSE') { Join-Path $projectRoot $name } else { Join-Path $consoleRoot $name }
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing runtime file: $name" }
    Copy-Item -LiteralPath $source -Destination (Join-Path $stageRoot $name)
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'powershell\CodexProxy.Core.psm1') -Destination (Join-Path $stageRoot 'powershell\CodexProxy.Core.psm1')

$versionText = ([IO.File]::ReadAllText((Join-Path $stageRoot 'VERSION'))).Trim()
if ($versionText -ne $Version) { throw "VERSION contains $versionText, expected $Version." }

Compress-Archive -Path (Join-Path $stageRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $entries = @($archive.Entries | ForEach-Object { ([string]$_.FullName).Replace('\', '/') })
    foreach ($required in @('启动修复.cmd', 'CodexProxyAssistant.ps1', 'powershell/CodexProxy.Core.psm1')) {
        if ($required -notin $entries) { throw "Release ZIP is missing root/runtime entry: $required" }
    }
    if (@($entries | Where-Object { $_ -match '(^|/)(tests|scripts|fixtures|release|artifacts)/' }).Count -gt 0) {
        throw 'Release ZIP contains development-only files.'
    }
    if (@($entries | Where-Object { $_ -match '^[^/]+/启动修复\.cmd$' }).Count -gt 0) {
        throw 'Release ZIP contains an unwanted wrapper directory.'
    }
} finally {
    $archive.Dispose()
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash.ToLowerInvariant()

if (-not $KeepStage) {
    Assert-WithinProject $stageRoot
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
    $releaseRoot = Split-Path -Parent $stageRoot
    if ((Test-Path -LiteralPath $releaseRoot -PathType Container) -and @(Get-ChildItem -LiteralPath $releaseRoot -Force).Count -eq 0) {
        Remove-Item -LiteralPath $releaseRoot -Force
    }
}

[pscustomobject]@{
    version = $Version
    zip = $zipPath
    bytes = (Get-Item -LiteralPath $zipPath).Length
    sha256 = $hash
    runtime_files = $runtimeFiles.Count + 1
} | ConvertTo-Json -Compress
