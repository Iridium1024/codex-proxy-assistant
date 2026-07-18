param(
    [Parameter(Mandatory = $true)]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$projectRoot = Split-Path -Parent $PSScriptRoot
$packageRoot = Join-Path $projectRoot 'release\CodexProxyAssistant'
$buildManifestPath = Join-Path $projectRoot 'release\build-manifest.json'
$artifactRoot = Join-Path $projectRoot 'artifacts'
$stagingRoot = Join-Path $artifactRoot '_staging'
$minimalRoot = Join-Path $stagingRoot 'minimal\CodexProxyAssistant'
$fullRoot = Join-Path $stagingRoot 'full\CodexProxyAssistant'
$minimalZip = Join-Path $artifactRoot ("CodexProxyAssistant-v{0}-minimal.zip" -f $Version)
$fullZip = Join-Path $artifactRoot ("CodexProxyAssistant-v{0}-windows-x64.zip" -f $Version)
$consoleZip = Join-Path $artifactRoot ("CodexProxyAssistant-Console-v{0}.zip" -f $Version)
$standaloneCmd = Join-Path $artifactRoot 'codex-vpn-repair.cmd'
$checksums = Join-Path $artifactRoot 'SHA256SUMS.txt'
$consolePackageScript = Join-Path $projectRoot 'console\scripts\package_release.ps1'
$projectFull = [IO.Path]::GetFullPath($projectRoot)
$artifactFull = [IO.Path]::GetFullPath($artifactRoot)

function Assert-ZipLayout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ZipPath,

        [Parameter(Mandatory = $true)]
        [string[]]$RequiredRootFiles
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $entryNames = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
    }
    finally {
        $archive.Dispose()
    }

    foreach ($requiredFile in $RequiredRootFiles) {
        if ($entryNames -notcontains $requiredFile) {
            throw "Release archive does not expose '$requiredFile' at its top level: $ZipPath"
        }
    }
    if (-not ($entryNames | Where-Object { $_.StartsWith('_internal/', [StringComparison]::OrdinalIgnoreCase) })) {
        throw "Release archive is missing the top-level _internal directory: $ZipPath"
    }
    if ($entryNames | Where-Object { $_.StartsWith('CodexProxyAssistant/', [StringComparison]::OrdinalIgnoreCase) }) {
        throw "Release archive contains an unnecessary CodexProxyAssistant wrapper directory: $ZipPath"
    }
    $forbidden = @($entryNames | Where-Object {
        $_ -match '(^|/)(tests?|fixtures?|\.github)/' -or
        $_ -match '(?i)fake[_-](codex|proxy)' -or
        $_ -match '(?i)localhost\.(crt|key)$' -or
        $_ -match '(?i)(^|/)BUILDING\.md$' -or
        $_ -match '(?i)(^|/)build-manifest\.json$' -or
        $_ -match '(?i)内部资料|前期调查|宏观目标|子步骤'
    })
    if ($forbidden.Count -gt 0) {
        throw ("Release archive contains test or internal material: {0}" -f ($forbidden -join ', '))
    }
}

if (-not $artifactFull.StartsWith($projectFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to manage artifacts outside the project: $artifactFull"
}
if (-not (Test-Path -LiteralPath (Join-Path $packageRoot 'CodexProxyAssistant.exe') -PathType Leaf)) {
    throw 'Build the application before creating GitHub release assets.'
}
if (-not (Test-Path -LiteralPath (Join-Path $packageRoot '_internal') -PathType Container)) {
    throw 'The required PyInstaller runtime directory is missing.'
}
if (-not (Test-Path -LiteralPath $buildManifestPath -PathType Leaf)) {
    throw 'The internal build manifest is missing; rebuild the application before packaging.'
}
$buildManifest = [IO.File]::ReadAllText($buildManifestPath) | ConvertFrom-Json
if ([string]$buildManifest.application_version -ne $Version) {
    throw ("Requested package version {0} does not match built application version {1}." -f $Version, $buildManifest.application_version)
}
$requiredSourceInputs = [ordered]@{
    'run_gui.py' = (Join-Path $projectRoot 'run_gui.py')
    'src/codex_proxy_assistant/main.py' = (Join-Path $projectRoot 'src\codex_proxy_assistant\main.py')
    'src/codex_proxy_assistant/main_window.py' = (Join-Path $projectRoot 'src\codex_proxy_assistant\main_window.py')
    'src/codex_proxy_assistant/theme.py' = (Join-Path $projectRoot 'src\codex_proxy_assistant\theme.py')
    'src/codex_proxy_assistant/backend.py' = (Join-Path $projectRoot 'src\codex_proxy_assistant\backend.py')
    'src/codex_proxy_assistant/workers.py' = (Join-Path $projectRoot 'src\codex_proxy_assistant\workers.py')
    'powershell/CodexProxy.Cli.ps1' = (Join-Path $projectRoot 'powershell\CodexProxy.Cli.ps1')
    'powershell/CodexProxy.Core.psm1' = (Join-Path $projectRoot 'powershell\CodexProxy.Core.psm1')
}
if (-not $buildManifest.source -or -not $buildManifest.source.inputs) {
    throw 'The build manifest has no source-input hashes; rebuild the GUI before packaging.'
}
foreach ($entry in $requiredSourceInputs.GetEnumerator()) {
    $manifestProperty = $buildManifest.source.inputs.PSObject.Properties[$entry.Key]
    if (-not $manifestProperty) {
        throw ("The build manifest does not cover source input: {0}" -f $entry.Key)
    }
    $currentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Value).Hash
    if ($currentHash -ne [string]$manifestProperty.Value) {
        throw ("The GUI release is stale; rebuild before packaging. Changed input: {0}" -f $entry.Key)
    }
}
$builtExe = Join-Path $packageRoot 'CodexProxyAssistant.exe'
$builtExeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $builtExe).Hash
if ($builtExeHash -ne [string]$buildManifest.executable.sha256) {
    throw 'The GUI executable hash does not match build-manifest.json.'
}

if (Test-Path -LiteralPath $artifactRoot) {
    Remove-Item -LiteralPath $artifactRoot -Recurse -Force
}
[void](New-Item -ItemType Directory -Path $minimalRoot -Force)
[void](New-Item -ItemType Directory -Path $fullRoot -Force)

Copy-Item -LiteralPath (Join-Path $packageRoot 'CodexProxyAssistant.exe') -Destination $minimalRoot
Copy-Item -LiteralPath (Join-Path $packageRoot '_internal') -Destination $minimalRoot -Recurse

Copy-Item -Path (Join-Path $packageRoot '*') -Destination $fullRoot -Recurse

Compress-Archive -Path (Join-Path $minimalRoot '*') -DestinationPath $minimalZip -CompressionLevel Optimal
Compress-Archive -Path (Join-Path $fullRoot '*') -DestinationPath $fullZip -CompressionLevel Optimal
Assert-ZipLayout -ZipPath $minimalZip -RequiredRootFiles @('CodexProxyAssistant.exe')
Assert-ZipLayout -ZipPath $fullZip -RequiredRootFiles @(
    'CodexProxyAssistant.exe',
    'README.md',
    'codex-vpn-repair.cmd'
)
Copy-Item -LiteralPath (Join-Path $projectRoot 'codex-vpn-repair.cmd') -Destination $standaloneCmd

Remove-Item -LiteralPath $stagingRoot -Recurse -Force

if (-not (Test-Path -LiteralPath $consolePackageScript -PathType Leaf)) {
    throw 'The PowerShell console packaging script is missing.'
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $consolePackageScript -Version $Version | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $consoleZip -PathType Leaf)) {
    throw 'PowerShell console packaging failed.'
}

$releaseFiles = @($consoleZip, $minimalZip, $fullZip, $standaloneCmd)
$checksumLines = foreach ($file in $releaseFiles) {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash.ToLowerInvariant()
    "{0}  {1}" -f $hash, [IO.Path]::GetFileName($file)
}
[IO.File]::WriteAllLines($checksums, $checksumLines, [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    version = $Version
    artifacts = @($releaseFiles + $checksums | ForEach-Object { [IO.Path]::GetFullPath($_) })
} | ConvertTo-Json -Depth 4
