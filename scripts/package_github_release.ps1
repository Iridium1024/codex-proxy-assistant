param(
    [Parameter(Mandatory = $true)]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$projectRoot = Split-Path -Parent $PSScriptRoot
$packageRoot = Join-Path $projectRoot 'release\CodexProxyAssistant'
$artifactRoot = Join-Path $projectRoot 'artifacts'
$stagingRoot = Join-Path $artifactRoot '_staging'
$minimalRoot = Join-Path $stagingRoot 'minimal\CodexProxyAssistant'
$fullRoot = Join-Path $stagingRoot 'full\CodexProxyAssistant'
$minimalZip = Join-Path $artifactRoot ("CodexProxyAssistant-v{0}-minimal.zip" -f $Version)
$fullZip = Join-Path $artifactRoot ("CodexProxyAssistant-v{0}-windows-x64.zip" -f $Version)
$standaloneCmd = Join-Path $artifactRoot 'codex-vpn-repair.cmd'
$checksums = Join-Path $artifactRoot 'SHA256SUMS.txt'
$projectFull = [IO.Path]::GetFullPath($projectRoot)
$artifactFull = [IO.Path]::GetFullPath($artifactRoot)

if (-not $artifactFull.StartsWith($projectFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to manage artifacts outside the project: $artifactFull"
}
if (-not (Test-Path -LiteralPath (Join-Path $packageRoot 'CodexProxyAssistant.exe') -PathType Leaf)) {
    throw 'Build the application before creating GitHub release assets.'
}
if (-not (Test-Path -LiteralPath (Join-Path $packageRoot '_internal') -PathType Container)) {
    throw 'The required PyInstaller runtime directory is missing.'
}

if (Test-Path -LiteralPath $artifactRoot) {
    Remove-Item -LiteralPath $artifactRoot -Recurse -Force
}
[void](New-Item -ItemType Directory -Path $minimalRoot -Force)
[void](New-Item -ItemType Directory -Path $fullRoot -Force)

Copy-Item -LiteralPath (Join-Path $packageRoot 'CodexProxyAssistant.exe') -Destination $minimalRoot
Copy-Item -LiteralPath (Join-Path $packageRoot '_internal') -Destination $minimalRoot -Recurse
Copy-Item -LiteralPath (Join-Path $packageRoot 'build-manifest.json') -Destination $minimalRoot

Copy-Item -Path (Join-Path $packageRoot '*') -Destination $fullRoot -Recurse

Compress-Archive -LiteralPath $minimalRoot -DestinationPath $minimalZip -CompressionLevel Optimal
Compress-Archive -LiteralPath $fullRoot -DestinationPath $fullZip -CompressionLevel Optimal
Copy-Item -LiteralPath (Join-Path $projectRoot 'codex-vpn-repair.cmd') -Destination $standaloneCmd

Remove-Item -LiteralPath $stagingRoot -Recurse -Force

$releaseFiles = @($minimalZip, $fullZip, $standaloneCmd)
$checksumLines = foreach ($file in $releaseFiles) {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash.ToLowerInvariant()
    "{0}  {1}" -f $hash, [IO.Path]::GetFileName($file)
}
[IO.File]::WriteAllLines($checksums, $checksumLines, [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    version = $Version
    artifacts = @($releaseFiles + $checksums | ForEach-Object { [IO.Path]::GetFullPath($_) })
} | ConvertTo-Json -Depth 4
