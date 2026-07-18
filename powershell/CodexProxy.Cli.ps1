param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('detect', 'check-codex', 'check-proxy', 'test-connection', 'plan', 'apply', 'list-snapshots', 'restore')]
    [string]$Action,
    [string]$CodexPath,
    [string]$ProxyEndpoint,
    [string]$ConfigPath,
    [string]$SnapshotId
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
Import-Module (Join-Path $PSScriptRoot 'CodexProxy.Core.psm1') -Force

$exitCode = 0
try {
    switch ($Action) {
        'detect' {
            $data = Get-DetectionReport -CodexPath $CodexPath -ConfigPath $ConfigPath
        }
        'check-codex' {
            if ([string]::IsNullOrWhiteSpace($CodexPath)) { throw 'CodexPath is required.' }
            $data = Get-CodexEngineInfo -Path $CodexPath
        }
        'check-proxy' {
            if ([string]::IsNullOrWhiteSpace($ProxyEndpoint)) { throw 'ProxyEndpoint is required.' }
            $data = Test-ProxyInput -Endpoint $ProxyEndpoint
        }
        'test-connection' {
            if ([string]::IsNullOrWhiteSpace($CodexPath)) { throw 'CodexPath is required.' }
            $data = Test-CodexConnection -CodexPath $CodexPath
        }
        'plan' {
            $data = Get-RepairPlan -CodexPath $CodexPath -ProxyEndpoint $ProxyEndpoint -ConfigPath $ConfigPath
        }
        'apply' {
            $data = Invoke-CodexProxyRepair -CodexPath $CodexPath -ProxyEndpoint $ProxyEndpoint -ConfigPath $ConfigPath
        }
        'list-snapshots' {
            $data = @(Get-ConfigSnapshots -ConfigPath $ConfigPath)
        }
        'restore' {
            if ([string]::IsNullOrWhiteSpace($SnapshotId)) { throw 'SnapshotId is required.' }
            $data = Restore-CodexProxySnapshot -SnapshotId $SnapshotId -CodexPath $CodexPath -ConfigPath $ConfigPath
        }
    }
    $result = [ordered]@{ ok = $true; action = $Action; data = $data; error = $null; exit_code = 0 }
} catch {
    $exitCode = 1
    $result = [ordered]@{ ok = $false; action = $Action; data = $null; error = $_.Exception.Message; exit_code = 1 }
}

$result | ConvertTo-Json -Depth 16 -Compress
exit $exitCode
