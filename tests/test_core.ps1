$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $projectRoot 'powershell\CodexProxy.Core.psm1'
$cliPath = Join-Path $projectRoot 'powershell\CodexProxy.Cli.ps1'
$codexCommand = @(Get-Command codex.cmd, codex.exe, codex -All -ErrorAction SilentlyContinue | Select-Object -First 1)
$codex = $(if ($codexCommand.Count -gt 0) { [string]$codexCommand[0].Path } else { $null })
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('CodexProxyAssistant-test-' + [Guid]::NewGuid().ToString('N'))
$oldCodexHome = $env:CODEX_HOME

try {
    [void](New-Item -ItemType Directory -Path $testRoot -Force)
    $env:CODEX_HOME = Join-Path $testRoot 'codex-home'
    [void](New-Item -ItemType Directory -Path $env:CODEX_HOME -Force)
    Import-Module $modulePath -Force

    $cases = @(
        @{ name = 'empty'; input = ''; expected = 'true' },
        @{ name = 'new section'; input = "model = 'x'`n"; expected = 'true' },
        @{ name = 'existing false'; input = "[features]`r`nrespect_system_proxy = false # keep`r`n"; expected = 'true' },
        @{ name = 'existing features'; input = "[features]`nother = true`n[tools]`nfoo = true`n"; expected = 'true' }
    )
    foreach ($case in $cases) {
        $updated = Enable-SystemProxyFeatureText -Text $case.input
        $state = Get-FeatureStateFromText -Text $updated
        if ($state -ne $case.expected) { throw "Transform case failed: $($case.name) => $state" }
    }

    $duplicateRaised = $false
    try { Enable-SystemProxyFeatureText -Text "[features]`na = true`n[features]`nb = true`n" | Out-Null } catch { $duplicateRaised = $true }
    if (-not $duplicateRaised) { throw 'Duplicate [features] sections were not rejected.' }

    $integration = 'skipped'
    $integrationReason = 'Codex CLI is not installed.'
    $snapshotId = $null
    $restoreSafetySnapshot = $null
    $snapshotCount = 0
    $restoredState = 'not-run'

    if ($codex -and (Test-Path -LiteralPath $codex -PathType Leaf)) {
        $codexInfo = Get-CodexEngineInfo -Path $codex
        $systemProxy = Get-WindowsSystemProxy
        $proxyReady = $systemProxy.configured -and
            ($systemProxy.source -ne 'manual' -or $systemProxy.tcp_reachable -eq $true)
        if (-not $codexInfo.supports_system_proxy) {
            $integrationReason = 'Installed Codex does not report respect_system_proxy support.'
        } elseif (-not $proxyReady) {
            $integrationReason = 'A reachable Windows system proxy is not configured.'
        } else {
            $applyRaw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cliPath -Action apply -CodexPath $codex
            $apply = ($applyRaw -join "`n") | ConvertFrom-Json
            if (-not $apply.ok -or -not $apply.data.changed) { throw "Apply failed: $($applyRaw -join ' ')" }
            $statusAfter = Get-CodexConfigStatus
            if ($statusAfter.feature_state -ne 'true') { throw 'Apply state is not true.' }

            $snapshotId = [string]$apply.data.snapshot_id
            $restoreRaw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cliPath -Action restore -SnapshotId $snapshotId -CodexPath $codex
            $restore = ($restoreRaw -join "`n") | ConvertFrom-Json
            if (-not $restore.ok -or -not $restore.data.restored) { throw "Restore failed: $($restoreRaw -join ' ')" }
            $statusRestored = Get-CodexConfigStatus
            if ($statusRestored.feature_state -ne 'missing' -or $statusRestored.exists) {
                throw 'Restore did not remove the originally absent config.'
            }

            $snapshots = @(Get-ConfigSnapshots)
            if ($snapshots.Count -ne 2 -or @($snapshots | Where-Object result -ne 'success').Count -ne 0) {
                throw 'Snapshot metadata validation failed.'
            }
            $integration = 'passed'
            $integrationReason = $null
            $restoreSafetySnapshot = $restore.data.safety_snapshot_id
            $snapshotCount = $snapshots.Count
            $restoredState = $statusRestored.feature_state
        }
    }

    [pscustomobject]@{
        transforms = $cases.Count
        duplicate_guard = $duplicateRaised
        integration = $integration
        integration_reason = $integrationReason
        apply_snapshot = $snapshotId
        restore_safety_snapshot = $restoreSafetySnapshot
        snapshots = $snapshotCount
        restored_state = $restoredState
    } | ConvertTo-Json -Compress
} finally {
    $env:CODEX_HOME = $oldCodexHome
    $fullTestRoot = [IO.Path]::GetFullPath($testRoot)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($fullTestRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($fullTestRoot).StartsWith('CodexProxyAssistant-test-', [StringComparison]::Ordinal)) {
        if ([IO.Directory]::Exists($fullTestRoot)) { [IO.Directory]::Delete($fullTestRoot, $true) }
    }
}
