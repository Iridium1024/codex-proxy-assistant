# This entrypoint is appended to CodexProxy.Core.psm1 by the release generator.
# Keep all business decisions in the core module; this file only handles text interaction.

$ErrorActionPreference = 'Stop'
$commandLineArgs = @($args)
$action = 'repair'
$dryRun = $false
$noPause = $false
$jsonMode = $false
$argumentError = $null

foreach ($argument in $commandLineArgs) {
    switch ($argument.ToLowerInvariant()) {
        'status'       { $action = 'status' }
        '--status'     { $action = 'status' }
        '/status'      { $action = 'status' }
        'repair'       { $action = 'repair' }
        '--repair'     { $action = 'repair' }
        '/repair'      { $action = 'repair' }
        'restore'      { $action = 'restore' }
        '--restore'    { $action = 'restore' }
        '/restore'     { $action = 'restore' }
        '--dry-run'    { $dryRun = $true }
        '/dry-run'     { $dryRun = $true }
        '-whatif'      { $dryRun = $true }
        '--no-pause'   { $noPause = $true }
        '/no-pause'    { $noPause = $true }
        '--json'       { $jsonMode = $true; $noPause = $true }
        default        { $argumentError = "Unknown argument: $argument" }
    }
}

function Write-StandaloneHeading {
    param([string]$Text)
    if ($jsonMode) { return }
    Write-Host ''
    Write-Host ("== {0} ==" -f $Text) -ForegroundColor Cyan
}

function Write-StandaloneStatus {
    param([string]$Level, [string]$Text)
    if ($jsonMode) { return }
    $color = switch ($Level) {
        'ok' { 'Green' }
        'warn' { 'Yellow' }
        'error' { 'Red' }
        default { 'Gray' }
    }
    $prefix = switch ($Level) {
        'ok' { '[OK]' }
        'warn' { '[WARN]' }
        'error' { '[ERROR]' }
        default { '[INFO]' }
    }
    Write-Host ("{0} {1}" -f $prefix, $Text) -ForegroundColor $color
}

function Show-StandaloneDetection {
    param([object]$Report)

    Write-StandaloneHeading 'Codex'
    if ($Report.recommended_path) {
        $selected = @($Report.engines | Where-Object { $_.path -eq $Report.recommended_path } | Select-Object -First 1)
        $targetLabel = $(if ($selected.Count -gt 0 -and $selected[0].kind -eq 'desktop') { 'Codex Desktop' } else { 'Codex CLI' })
        if ($selected.Count -gt 0 -and $selected[0].supports_system_proxy) {
            Write-StandaloneStatus 'ok' ("Current target: {0}, {1}, system proxy supported." -f $targetLabel, $selected[0].version)
        } else {
            Write-StandaloneStatus 'warn' ("Current target: {0}. Update Codex or select another installation." -f $targetLabel)
        }
    } else {
        Write-StandaloneStatus 'error' 'No runnable Codex Desktop or CLI engine was found.'
    }

    Write-StandaloneHeading 'Windows proxy'
    if (-not $Report.proxy.configured) {
        Write-StandaloneStatus 'warn' 'Windows system proxy, PAC, or automatic discovery is not enabled.'
    } elseif ($Report.proxy.source -eq 'manual' -and $Report.proxy.tcp_reachable -ne $true) {
        Write-StandaloneStatus 'error' 'The configured Windows proxy port is not reachable.'
    } elseif ($Report.proxy.source -eq 'manual' -and $Report.proxy.https_reachable -eq $true) {
        Write-StandaloneStatus 'ok' ("The Windows proxy can reach HTTPS: {0}" -f $Report.proxy.display_endpoint)
    } elseif ($Report.proxy.source -eq 'manual') {
        Write-StandaloneStatus 'error' 'The proxy port is open, but the HTTPS route test failed. Check the HTTP or Mixed port.'
    } else {
        Write-StandaloneStatus 'warn' ("{0} is configured; static endpoint validation is unavailable and Codex will resolve it at runtime." -f $Report.proxy.source.ToUpperInvariant())
    }
    foreach ($skipped in @($Report.skipped)) {
        Write-StandaloneStatus 'warn' ("Skipped an unresponsive or unverifiable Codex candidate: {0}" -f $skipped.path)
    }

    Write-StandaloneHeading 'Codex configuration'
    Write-StandaloneStatus 'info' ("Config: {0}" -f $Report.config.path)
    Write-StandaloneStatus $(if ($Report.config.feature_state -eq 'true') { 'ok' } else { 'warn' }) ("System-proxy setting: {0}" -f $Report.config.feature_state)
}

$exitCode = 0
$data = $null
$errorText = $null
try {
    if ($argumentError) { throw $argumentError }
    if (-not $jsonMode) {
        Write-Host 'Codex VPN / system-proxy repair' -ForegroundColor White
        Write-Host ("Action: {0}{1}" -f $action, $(if ($dryRun) { ' (dry run)' } else { '' }))
    }

    switch ($action) {
        'status' {
            $data = Get-DetectionReport
            Show-StandaloneDetection -Report $data
            if (-not $data.recommended_path -or -not $data.proxy.configured) { $exitCode = 2 }
        }
        'repair' {
            $plan = Get-RepairPlan
            $data = $plan
            if ($dryRun) {
                if (-not $jsonMode) {
                    Show-StandaloneDetection -Report (Get-DetectionReport)
                    Write-StandaloneHeading 'Repair preview'
                    if ($plan.can_apply) {
                        Write-StandaloneStatus 'ok' ("Would set system-proxy support: {0} -> {1}" -f $plan.before_state, $plan.after_state)
                    } else {
                        foreach ($message in @($plan.errors)) { Write-StandaloneStatus 'error' ([string]$message) }
                    }
                }
                if (-not $plan.can_apply) { $exitCode = 3 }
            } elseif (-not $plan.can_apply) {
                foreach ($message in @($plan.errors)) { Write-StandaloneStatus 'error' ([string]$message) }
                $exitCode = 3
            } else {
                $data = Invoke-CodexProxyRepair
                Write-StandaloneStatus 'ok' ([string]$data.message)
                if ($data.snapshot_id) { Write-StandaloneStatus 'info' ("Snapshot: {0}" -f $data.snapshot_id) }
                Write-StandaloneStatus 'info' 'Fully exit and restart Codex, then test the connection.'
            }
        }
        'restore' {
            $snapshots = @(Get-ConfigSnapshots | Where-Object { $_.operation -eq 'apply' -and $_.result -eq 'success' })
            if ($snapshots.Count -eq 0) { throw 'No successful apply snapshot is available to restore.' }
            $target = $snapshots[0]
            if ($dryRun) {
                $data = [pscustomobject]@{ snapshot_id = $target.id; would_restore = $true }
                Write-StandaloneStatus 'info' ("Would restore snapshot: {0}" -f $target.id)
            } else {
                $data = Restore-CodexProxySnapshot -SnapshotId $target.id
                Write-StandaloneStatus 'ok' ([string]$data.message)
                Write-StandaloneStatus 'info' ("Safety snapshot: {0}" -f $data.safety_snapshot_id)
            }
        }
    }
} catch {
    if ($exitCode -eq 0) { $exitCode = 1 }
    $errorText = $_.Exception.Message
    Write-StandaloneStatus 'error' $errorText
}

if ($jsonMode) {
    [ordered]@{
        ok = ($exitCode -eq 0)
        action = $action
        dry_run = $dryRun
        data = $data
        error = $errorText
        exit_code = $exitCode
    } | ConvertTo-Json -Depth 16 -Compress
}

if (-not $noPause) {
    Write-Host ''
    [void](Read-Host 'Press Enter to close')
}
exit $exitCode
