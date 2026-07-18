param(
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$projectRoot = Split-Path -Parent $PSScriptRoot
$corePath = Join-Path $projectRoot 'powershell\CodexProxy.Core.psm1'
$entryPath = Join-Path $projectRoot 'powershell\CodexProxy.Standalone.ps1'
$outputPath = Join-Path $projectRoot 'codex-vpn-repair.cmd'
$utf8 = New-Object Text.UTF8Encoding($false)

foreach ($path in @($corePath, $entryPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing standalone source: $path" }
}

$batchHeader = @'
@echo off
setlocal
set "CODEX_VPN_REPAIR_SELF=%~f0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$raw=[IO.File]::ReadAllText($env:CODEX_VPN_REPAIR_SELF); $parts=$raw -split '(?m)^:POWERSHELL_PAYLOAD\r?$'; if($parts.Count -lt 2){Write-Error 'Embedded PowerShell payload is missing.'; exit 90}; & ([ScriptBlock]::Create($parts[$parts.Count-1])) @args" %*
set "CODEX_VPN_REPAIR_EXIT=%ERRORLEVEL%"
endlocal & exit /b %CODEX_VPN_REPAIR_EXIT%

:POWERSHELL_PAYLOAD
# GENERATED FILE. Edit powershell\CodexProxy.Core.psm1 or CodexProxy.Standalone.ps1.
'@

function ConvertTo-Crlf {
    param([string]$Text)
    return (($Text -replace "`r`n", "`n") -replace "`r", "`n") -replace "`n", "`r`n"
}

$core = [IO.File]::ReadAllText($corePath)
$entry = [IO.File]::ReadAllText($entryPath)
$generated = (ConvertTo-Crlf -Text $batchHeader).TrimEnd("`r", "`n") + "`r`n" +
    (ConvertTo-Crlf -Text $core).TrimEnd("`r", "`n") + "`r`n`r`n" +
    (ConvertTo-Crlf -Text $entry).TrimEnd("`r", "`n") + "`r`n"

if ($Check) {
    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw 'The generated standalone CMD is missing.' }
    $existing = [IO.File]::ReadAllText($outputPath)
    if ($existing -cne $generated) {
        throw 'codex-vpn-repair.cmd is stale. Run scripts\generate_standalone_cmd.ps1.'
    }
    Write-Host 'Standalone CMD is up to date.'
    exit 0
}

[IO.File]::WriteAllText($outputPath, $generated, $utf8)
Write-Host "Generated: $outputPath"
