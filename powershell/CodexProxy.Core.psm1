Set-StrictMode -Version 2.0

$script:FeatureName = 'respect_system_proxy'
$script:SnapshotSchemaVersion = 1

function Get-TextSha256 {
    param([string]$Text)

    $encoding = New-Object Text.UTF8Encoding($false)
    $bytes = $encoding.GetBytes([string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash) -replace '-', '')
    } finally {
        $sha.Dispose()
    }
}

function Write-Utf8Text {
    param(
        [string]$Path,
        [string]$Text
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )

    Write-Utf8Text -Path $Path -Text (($Value | ConvertTo-Json -Depth 16) + "`r`n")
}

function Get-CodexConfigPath {
    param([string]$ConfigPath)

    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($ConfigPath))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        return [IO.Path]::GetFullPath((Join-Path $env:CODEX_HOME 'config.toml'))
    }
    $userProfile = [Environment]::GetFolderPath('UserProfile')
    return [IO.Path]::GetFullPath((Join-Path (Join-Path $userProfile '.codex') 'config.toml'))
}

function Get-FeatureStateFromText {
    param([string]$Text)

    $lines = @([regex]::Split([string]$Text, '\r?\n'))
    $sections = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[features\]\s*(?:#.*)?$') { $sections += $i }
    }
    if ($sections.Count -gt 1) { return 'invalid-duplicate-section' }
    if ($sections.Count -eq 0) { return 'missing' }

    $start = [int]$sections[0] + 1
    $end = $lines.Count
    for ($i = $start; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[[^\]]+\]\s*(?:#.*)?$') {
            $end = $i
            break
        }
    }

    $values = @()
    for ($i = $start; $i -lt $end; $i++) {
        if ($lines[$i] -match '^\s*respect_system_proxy\s*=\s*(true|false)\s*(?:#.*)?$') {
            $values += $matches[1].ToLowerInvariant()
        } elseif ($lines[$i] -match '^\s*respect_system_proxy\s*=') {
            return 'invalid-value'
        }
    }
    if ($values.Count -gt 1) { return 'invalid-duplicate-key' }
    if ($values.Count -eq 0) { return 'missing' }
    return $values[0]
}

function Enable-SystemProxyFeatureText {
    param([string]$Text)

    $newline = "`r`n"
    if ($Text -notmatch "`r`n" -and $Text -match "`n") { $newline = "`n" }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in [regex]::Split([string]$Text, '\r?\n')) { [void]$lines.Add($line) }
    if ([string]$Text -eq '') { $lines.Clear() }

    $sections = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[features\]\s*(?:#.*)?$') { $sections += $i }
    }
    if ($sections.Count -gt 1) { throw 'config.toml contains more than one [features] section.' }

    if ($sections.Count -eq 0) {
        if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
            $lines.Add('')
        }
        $lines.Add('[features]')
        $lines.Add('respect_system_proxy = true')
        return (($lines -join $newline).TrimEnd("`r", "`n") + $newline)
    }

    $start = [int]$sections[0] + 1
    $end = $lines.Count
    for ($i = $start; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[[^\]]+\]\s*(?:#.*)?$') {
            $end = $i
            break
        }
    }

    $keys = @()
    for ($i = $start; $i -lt $end; $i++) {
        if ($lines[$i] -match '^\s*respect_system_proxy\s*=') { $keys += $i }
    }
    if ($keys.Count -gt 1) { throw 'The [features] section contains duplicate respect_system_proxy keys.' }
    if ($keys.Count -eq 1) {
        $index = [int]$keys[0]
        if ($lines[$index] -notmatch '^(\s*respect_system_proxy\s*=\s*)(true|false)(\s*(?:#.*)?)$') {
            throw 'respect_system_proxy exists but is not a simple true/false value.'
        }
        $lines[$index] = $matches[1] + 'true' + $matches[3]
    } else {
        $lines.Insert($end, 'respect_system_proxy = true')
    }
    return (($lines -join $newline).TrimEnd("`r", "`n") + $newline)
}

function Get-CodexConfigStatus {
    param([string]$ConfigPath)

    $path = Get-CodexConfigPath -ConfigPath $ConfigPath
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    $text = ''
    if ($exists) { $text = [IO.File]::ReadAllText($path) }
    return [pscustomobject]@{
        path = $path
        exists = [bool]$exists
        feature_state = Get-FeatureStateFromText -Text $text
        sha256 = $(if ($exists) { Get-TextSha256 -Text $text } else { $null })
        snapshot_root = Get-SnapshotRoot -ConfigPath $path
    }
}

function Write-ConfigAtomically {
    param(
        [string]$Path,
        [string]$Text
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }
    $temporary = Join-Path $directory ('.codex-proxy-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        Write-Utf8Text -Path $temporary -Text $Text
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [IO.File]::Replace($temporary, $Path, $null, $true)
        } else {
            [IO.File]::Move($temporary, $Path)
        }
    } finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            [IO.File]::Delete($temporary)
        }
    }
}

function Restore-ConfigContent {
    param(
        [string]$Path,
        [bool]$Exists,
        [string]$Text
    )

    if ($Exists) {
        Write-ConfigAtomically -Path $Path -Text $Text
    } elseif (Test-Path -LiteralPath $Path -PathType Leaf) {
        [IO.File]::Delete($Path)
    }
}

function Add-CodexInstallation {
    param(
        [System.Collections.ArrayList]$List,
        [hashtable]$Seen,
        [string]$Path,
        [string]$Source,
        [string]$Kind,
        [bool]$Runnable
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try { $fullPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)) } catch { return }
    $key = $fullPath.ToLowerInvariant()
    if ($Seen.ContainsKey($key) -or -not (Test-Path -LiteralPath $fullPath)) { return }
    $Seen[$key] = $true
    [void]$List.Add([pscustomobject]@{
        path = $fullPath
        source = $Source
        kind = $Kind
        runnable = $Runnable
    })
}

function Get-CodexInstallations {
    $items = New-Object System.Collections.ArrayList
    $seen = @{}

    try {
        foreach ($command in @(Get-Command codex.cmd, codex.exe, codex -All -ErrorAction SilentlyContinue)) {
            $path = $command.Path
            if ([string]::IsNullOrWhiteSpace($path)) { $path = $command.Source }
            if ([IO.Path]::GetExtension([string]$path) -in @('.cmd', '.bat', '.exe')) {
                Add-CodexInstallation $items $seen $path 'PATH' 'engine' $true
            }
        }
    } catch { }

    $common = @()
    if ($env:APPDATA) { $common += (Join-Path $env:APPDATA 'npm\codex.cmd') }
    if ($env:LOCALAPPDATA) {
        $common += (Join-Path $env:LOCALAPPDATA 'Programs\Codex\resources\codex.exe')
        $common += (Join-Path $env:LOCALAPPDATA 'Programs\Codex\codex.exe')
    }
    if ($env:ProgramFiles) {
        $common += (Join-Path $env:ProgramFiles 'Codex\resources\codex.exe')
        $common += (Join-Path $env:ProgramFiles 'Codex\codex.exe')
    }
    foreach ($path in $common) { Add-CodexInstallation $items $seen $path 'common path' 'engine' $true }

    try {
        foreach ($package in @(Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue)) {
            Add-CodexInstallation $items $seen (Join-Path $package.InstallLocation 'app\resources\codex.exe') ("Desktop package {0}" -f $package.Version) 'desktop-engine' $true
            Add-CodexInstallation $items $seen $package.InstallLocation ("Desktop package {0}" -f $package.Version) 'desktop-package' $false
        }
    } catch { }

    try {
        foreach ($process in @(Get-CimInstance Win32_Process -Filter "Name='codex.exe'" -ErrorAction SilentlyContinue)) {
            Add-CodexInstallation $items $seen $process.ExecutablePath 'running process' 'engine' $true
        }
    } catch { }
    return @($items)
}

function Get-CodexEngineInfo {
    param([Parameter(Mandatory = $true)][string]$Path)

    $expanded = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))
    if (-not (Test-Path -LiteralPath $expanded -PathType Leaf)) {
        return [pscustomobject]@{
            path = $expanded; exists = $false; runnable = $false; version = 'unknown'
            supports_system_proxy = $false; feature_enabled = $false; error = 'File not found.'
        }
    }

    $version = 'unknown'
    $supports = $false
    $enabled = $false
    $errorText = $null
    $oldAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $versionOutput = @(& $expanded --version 2>&1)
        $versionLine = @($versionOutput | Where-Object { [string]$_ -match '^codex-cli\s+' } | Select-Object -First 1)
        if ($versionLine.Count -gt 0) { $version = ([string]$versionLine[0]).Trim() }
        $featureOutput = @(& $expanded features list 2>&1)
        $featureLine = @($featureOutput | Where-Object { [string]$_ -match '^respect_system_proxy\s+' } | Select-Object -First 1)
        if ($featureLine.Count -gt 0) {
            $supports = $true
            $enabled = ([string]$featureLine[0] -match '\s+true\s*$')
        }
        if ($version -eq 'unknown' -and -not $supports) {
            $errorText = (($versionOutput + $featureOutput | ForEach-Object { [string]$_ }) -join ' ').Trim()
            if ([string]::IsNullOrWhiteSpace($errorText)) { $errorText = 'The executable could not be verified.' }
        }
    } catch {
        $errorText = $_.Exception.Message
    } finally {
        $ErrorActionPreference = $oldAction
    }
    return [pscustomobject]@{
        path = $expanded
        exists = $true
        runnable = [bool]($supports -or $version -ne 'unknown')
        version = $version
        supports_system_proxy = $supports
        feature_enabled = $enabled
        error = $errorText
    }
}

function ConvertTo-ProxyEndpoint {
    param([string]$Endpoint)

    if ([string]::IsNullOrWhiteSpace($Endpoint)) { return $null }
    $value = $Endpoint.Trim()
    if ($value -notmatch '^[a-z][a-z0-9+.-]*://') { $value = 'http://' + $value }
    try {
        $uri = New-Object Uri($value)
        if ([string]::IsNullOrWhiteSpace($uri.Host) -or $uri.Port -lt 1) { return $null }
        $hostDisplay = $uri.Host
        if ($hostDisplay.Contains(':') -and -not $hostDisplay.StartsWith('[')) { $hostDisplay = '[' + $hostDisplay + ']' }
        return [pscustomobject]@{
            valid = $true
            scheme = $uri.Scheme.ToLowerInvariant()
            host = $uri.Host
            port = [int]$uri.Port
            normalized = ("{0}://{1}:{2}" -f $uri.Scheme.ToLowerInvariant(), $hostDisplay, $uri.Port)
            display = ("{0}://{1}:{2}" -f $uri.Scheme.ToLowerInvariant(), $hostDisplay, $uri.Port)
            has_credentials = -not [string]::IsNullOrWhiteSpace($uri.UserInfo)
        }
    } catch {
        return $null
    }
}

function Test-TcpEndpoint {
    param(
        [string]$HostName,
        [int]$Port,
        [int]$TimeoutMilliseconds = 1800
    )

    $client = New-Object Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false)) { return $false }
        $client.EndConnect($async)
        return [bool]$client.Connected
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Get-WindowsSystemProxy {
    $enabled = $false
    $server = ''
    $pac = ''
    $autoDetect = $false
    $readError = $null
    try {
        $settings = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        $enabled = ([int]$settings.ProxyEnable -eq 1)
        if ($settings.PSObject.Properties['ProxyServer']) { $server = [string]$settings.ProxyServer }
        if ($settings.PSObject.Properties['AutoConfigURL']) { $pac = [string]$settings.AutoConfigURL }
        if ($settings.PSObject.Properties['AutoDetect']) { $autoDetect = ([int]$settings.AutoDetect -eq 1) }
    } catch {
        $readError = $_.Exception.Message
    }

    $endpointText = $null
    if (-not [string]::IsNullOrWhiteSpace($server)) {
        $entries = @{}
        foreach ($piece in ($server -split ';')) {
            $trimmed = $piece.Trim()
            if ($trimmed -match '^([^=]+)=(.+)$') {
                $entries[$matches[1].ToLowerInvariant()] = $matches[2].Trim()
            } elseif (-not $endpointText) { $endpointText = $trimmed }
        }
        foreach ($name in @('https', 'http', 'socks')) {
            if ($entries.ContainsKey($name)) { $endpointText = $entries[$name]; break }
        }
    }
    $endpoint = ConvertTo-ProxyEndpoint -Endpoint $endpointText
    $reachable = $null
    if ($endpoint) { $reachable = Test-TcpEndpoint -HostName $endpoint.host -Port $endpoint.port }

    $source = 'none'
    if ($enabled -and $endpoint) { $source = 'manual' }
    elseif (-not [string]::IsNullOrWhiteSpace($pac)) { $source = 'pac' }
    elseif ($autoDetect) { $source = 'wpad' }

    $pacDisplay = $null
    if (-not [string]::IsNullOrWhiteSpace($pac)) {
        try {
            $pacUri = New-Object Uri($pac)
            $pacDisplay = $pacUri.GetLeftPart([UriPartial]::Path)
        } catch { $pacDisplay = 'configured' }
    }
    return [pscustomobject]@{
        configured = [bool]($source -ne 'none')
        enabled = $enabled
        source = $source
        endpoint = $(if ($endpoint) { $endpoint.normalized } else { $null })
        display_endpoint = $(if ($endpoint) { $endpoint.display } else { $null })
        host = $(if ($endpoint) { $endpoint.host } else { $null })
        port = $(if ($endpoint) { $endpoint.port } else { $null })
        tcp_reachable = $reachable
        pac_url = $pacDisplay
        auto_detect = $autoDetect
        error = $readError
    }
}

function Test-ProxyInput {
    param(
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [int]$TimeoutMilliseconds = 1800
    )

    $parsed = ConvertTo-ProxyEndpoint -Endpoint $Endpoint
    if (-not $parsed) {
        return [pscustomobject]@{
            valid = $false; display_endpoint = $null; host = $null; port = $null
            tcp_reachable = $false; matches_system = $false; has_credentials = $false
            error = 'Proxy must be a host:port or a valid proxy URL.'
        }
    }
    $system = Get-WindowsSystemProxy
    $matchesSystem = $false
    if ($system.endpoint) {
        $systemParsed = ConvertTo-ProxyEndpoint -Endpoint $system.endpoint
        $matchesSystem = ($systemParsed.host.Equals($parsed.host, [StringComparison]::OrdinalIgnoreCase) -and $systemParsed.port -eq $parsed.port)
    }
    return [pscustomobject]@{
        valid = $true
        display_endpoint = $parsed.display
        normalized = $parsed.normalized
        host = $parsed.host
        port = $parsed.port
        tcp_reachable = Test-TcpEndpoint -HostName $parsed.host -Port $parsed.port -TimeoutMilliseconds $TimeoutMilliseconds
        matches_system = $matchesSystem
        has_credentials = $parsed.has_credentials
        error = $null
    }
}

function Get-SnapshotRoot {
    param([string]$ConfigPath)
    return (Join-Path (Split-Path -Parent $ConfigPath) 'proxy-config-snapshots')
}

function New-ConfigSnapshot {
    param(
        [string]$ConfigPath,
        [string]$Operation,
        [bool]$BeforeExists,
        [string]$BeforeText,
        [bool]$AfterExists,
        [string]$AfterText,
        [object]$CodexInfo,
        [object]$ProxyInfo,
        [string]$TargetSnapshotId
    )

    $root = Get-SnapshotRoot -ConfigPath $ConfigPath
    if (-not (Test-Path -LiteralPath $root)) { [void](New-Item -ItemType Directory -Path $root -Force) }
    $id = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 6)
    $folder = Join-Path $root $id
    [void](New-Item -ItemType Directory -Path $folder -Force)
    if ($BeforeExists) { Write-Utf8Text -Path (Join-Path $folder 'config.before.toml') -Text $BeforeText }
    if ($AfterExists) { Write-Utf8Text -Path (Join-Path $folder 'config.after.toml') -Text $AfterText }

    $metadata = [ordered]@{
        schema_version = $script:SnapshotSchemaVersion
        id = $id
        operation = $Operation
        created_at_local = [DateTimeOffset]::Now.ToString('o')
        created_at_utc = [DateTimeOffset]::UtcNow.ToString('o')
        config_path = $ConfigPath
        target_snapshot_id = $TargetSnapshotId
        before = [ordered]@{
            exists = $BeforeExists
            feature_state = Get-FeatureStateFromText -Text $BeforeText
            sha256 = $(if ($BeforeExists) { Get-TextSha256 -Text $BeforeText } else { $null })
        }
        after = [ordered]@{
            exists = $AfterExists
            feature_state = Get-FeatureStateFromText -Text $AfterText
            sha256 = $(if ($AfterExists) { Get-TextSha256 -Text $AfterText } else { $null })
        }
        codex = $(if ($CodexInfo) { [ordered]@{ path = $CodexInfo.path; version = $CodexInfo.version } } else { $null })
        proxy = $(if ($ProxyInfo) { [ordered]@{ source = $ProxyInfo.source; endpoint = $ProxyInfo.display_endpoint; tcp_reachable = $ProxyInfo.tcp_reachable } } else { $null })
        result = 'pending'
        error = $null
    }
    $metadataPath = Join-Path $folder 'snapshot.json'
    Write-JsonFile -Path $metadataPath -Value $metadata
    return [pscustomobject]@{ id = $id; folder = $folder; metadata_path = $metadataPath; metadata = [pscustomobject]$metadata }
}

function Update-SnapshotResult {
    param(
        [object]$Snapshot,
        [string]$Result,
        [string]$ErrorText
    )

    $metadata = [IO.File]::ReadAllText($Snapshot.metadata_path) | ConvertFrom-Json
    $metadata.result = $Result
    $metadata.error = $ErrorText
    $metadata | Add-Member -NotePropertyName completed_at_local -NotePropertyValue ([DateTimeOffset]::Now.ToString('o')) -Force
    $metadata | Add-Member -NotePropertyName completed_at_utc -NotePropertyValue ([DateTimeOffset]::UtcNow.ToString('o')) -Force
    Write-JsonFile -Path $Snapshot.metadata_path -Value $metadata
}

function Get-ConfigSnapshots {
    param([string]$ConfigPath)

    $path = Get-CodexConfigPath -ConfigPath $ConfigPath
    $root = Get-SnapshotRoot -ConfigPath $path
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return @() }
    $items = @()
    foreach ($folder in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        $metadataPath = Join-Path $folder.FullName 'snapshot.json'
        if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) { continue }
        try {
            $metadata = [IO.File]::ReadAllText($metadataPath) | ConvertFrom-Json
            $items += [pscustomobject]@{
                id = $metadata.id
                operation = $metadata.operation
                created_at_local = $metadata.created_at_local
                created_at_utc = $metadata.created_at_utc
                before_state = $metadata.before.feature_state
                after_state = $metadata.after.feature_state
                result = $metadata.result
                codex_version = $(if ($metadata.codex) { $metadata.codex.version } else { $null })
                folder = $folder.FullName
            }
        } catch { }
    }
    return @($items | Sort-Object created_at_utc -Descending)
}

function Get-RecommendedCodexInfo {
    param([string]$CodexPath)

    if (-not [string]::IsNullOrWhiteSpace($CodexPath)) { return Get-CodexEngineInfo -Path $CodexPath }
    $fallback = $null
    foreach ($installation in @(Get-CodexInstallations | Where-Object { $_.runnable })) {
        $info = Get-CodexEngineInfo -Path $installation.path
        if ($info.supports_system_proxy) { return $info }
        if (-not $fallback -and $info.runnable) { $fallback = $info }
    }
    return $fallback
}

function Get-DetectionReport {
    param(
        [string]$CodexPath,
        [string]$ConfigPath
    )

    $installations = @(Get-CodexInstallations)
    if (-not [string]::IsNullOrWhiteSpace($CodexPath) -and -not ($installations.path -contains $CodexPath)) {
        $installations = @([pscustomobject]@{ path = $CodexPath; source = 'user'; kind = 'engine'; runnable = $true }) + $installations
    }
    $engines = @()
    foreach ($installation in @($installations | Where-Object { $_.runnable })) {
        $engines += Get-CodexEngineInfo -Path $installation.path
    }
    $recommended = @($engines | Where-Object { $_.supports_system_proxy } | Select-Object -First 1)
    if ($recommended.Count -eq 0) { $recommended = @($engines | Where-Object { $_.runnable } | Select-Object -First 1) }
    return [pscustomobject]@{
        installations = $installations
        engines = $engines
        recommended_path = $(if ($recommended.Count -gt 0) { $recommended[0].path } else { $null })
        proxy = Get-WindowsSystemProxy
        config = Get-CodexConfigStatus -ConfigPath $ConfigPath
        snapshots = @(Get-ConfigSnapshots -ConfigPath $ConfigPath)
    }
}

function Get-RepairPlan {
    param(
        [string]$CodexPath,
        [string]$ProxyEndpoint,
        [string]$ConfigPath
    )

    $codex = Get-RecommendedCodexInfo -CodexPath $CodexPath
    $systemProxy = Get-WindowsSystemProxy
    $proxyInput = $null
    if (-not [string]::IsNullOrWhiteSpace($ProxyEndpoint)) { $proxyInput = Test-ProxyInput -Endpoint $ProxyEndpoint }
    $config = Get-CodexConfigStatus -ConfigPath $ConfigPath
    $warnings = New-Object System.Collections.ArrayList
    $errors = New-Object System.Collections.ArrayList
    $needsChange = ($config.feature_state -ne 'true')

    if ($config.feature_state -like 'invalid-*') { [void]$errors.Add('The existing config has an unsafe or duplicate [features] value.') }
    if ($needsChange) {
        if (-not $codex) { [void]$errors.Add('No runnable Codex engine was found.') }
        elseif (-not $codex.supports_system_proxy) { [void]$errors.Add('The selected Codex engine did not confirm respect_system_proxy support.') }
        if (-not $systemProxy.configured) { [void]$errors.Add('Windows system proxy, PAC, or WPAD is not enabled.') }
        if ($systemProxy.source -eq 'manual' -and $systemProxy.tcp_reachable -ne $true) { [void]$errors.Add('The configured Windows proxy port is not reachable.') }
        if ($proxyInput) {
            if (-not $proxyInput.valid -or -not $proxyInput.tcp_reachable) { [void]$errors.Add('The proxy entered in the UI is invalid or unreachable.') }
            elseif ($systemProxy.source -eq 'manual' -and -not $proxyInput.matches_system) {
                [void]$errors.Add('The entered proxy differs from the Windows system proxy; persistent repair would not use it.')
            }
            if ($proxyInput.has_credentials) { [void]$errors.Add('Proxy URLs containing a user name or password are not accepted.') }
        }
    } else {
        [void]$warnings.Add('The persistent setting is already enabled; applying would make no change.')
    }

    return [pscustomobject]@{
        can_apply = ($errors.Count -eq 0)
        needs_change = $needsChange
        config = $config
        codex = $codex
        system_proxy = $systemProxy
        proxy_input = $proxyInput
        before_state = $config.feature_state
        after_state = 'true'
        warnings = @($warnings)
        errors = @($errors)
    }
}

function Test-CodexExpectedFeature {
    param(
        [object]$CodexInfo,
        [string]$ExpectedState
    )

    if (-not $CodexInfo -or -not $CodexInfo.supports_system_proxy) { throw 'No verified Codex engine is available for post-write validation.' }
    $oldAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $CodexInfo.path features list 2>&1)
    } finally {
        $ErrorActionPreference = $oldAction
    }
    $line = @($output | Where-Object { [string]$_ -match '^respect_system_proxy\s+' } | Select-Object -First 1)
    if ($line.Count -eq 0) { throw 'Codex did not report respect_system_proxy after the write.' }
    $actual = $(if ([string]$line[0] -match '\s+true\s*$') { 'true' } else { 'false' })
    $expected = $(if ($ExpectedState -eq 'true') { 'true' } else { 'false' })
    if ($actual -ne $expected) { throw ("Codex reported {0}, expected {1}." -f $actual, $expected) }
}

function Invoke-CodexProxyRepair {
    param(
        [string]$CodexPath,
        [string]$ProxyEndpoint,
        [string]$ConfigPath
    )

    $plan = Get-RepairPlan -CodexPath $CodexPath -ProxyEndpoint $ProxyEndpoint -ConfigPath $ConfigPath
    if (-not $plan.can_apply) { throw (($plan.errors | ForEach-Object { [string]$_ }) -join ' ') }
    if (-not $plan.needs_change) {
        return [pscustomobject]@{ changed = $false; snapshot_id = $null; config = $plan.config; message = 'Configuration is already enabled.' }
    }

    $path = $plan.config.path
    $beforeExists = Test-Path -LiteralPath $path -PathType Leaf
    $beforeText = $(if ($beforeExists) { [IO.File]::ReadAllText($path) } else { '' })
    $afterText = Enable-SystemProxyFeatureText -Text $beforeText
    $snapshot = New-ConfigSnapshot -ConfigPath $path -Operation 'apply' -BeforeExists $beforeExists -BeforeText $beforeText -AfterExists $true -AfterText $afterText -CodexInfo $plan.codex -ProxyInfo $plan.system_proxy
    try {
        Write-ConfigAtomically -Path $path -Text $afterText
        $status = Get-CodexConfigStatus -ConfigPath $path
        if ($status.feature_state -ne 'true') { throw 'The written config did not pass local parsing verification.' }
        Test-CodexExpectedFeature -CodexInfo $plan.codex -ExpectedState 'true'
        Update-SnapshotResult -Snapshot $snapshot -Result 'success' -ErrorText $null
        return [pscustomobject]@{ changed = $true; snapshot_id = $snapshot.id; snapshot_folder = $snapshot.folder; config = $status; message = 'Persistent Codex system-proxy support was enabled.' }
    } catch {
        Restore-ConfigContent -Path $path -Exists $beforeExists -Text $beforeText
        Update-SnapshotResult -Snapshot $snapshot -Result 'rolled_back' -ErrorText $_.Exception.Message
        throw ("Repair verification failed and the original config was restored. {0}" -f $_.Exception.Message)
    }
}

function Restore-CodexProxySnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$SnapshotId,
        [string]$CodexPath,
        [string]$ConfigPath
    )

    $path = Get-CodexConfigPath -ConfigPath $ConfigPath
    $targetFolder = Join-Path (Get-SnapshotRoot -ConfigPath $path) $SnapshotId
    $targetMetadataPath = Join-Path $targetFolder 'snapshot.json'
    if (-not (Test-Path -LiteralPath $targetMetadataPath -PathType Leaf)) { throw 'The selected snapshot does not exist.' }
    $target = [IO.File]::ReadAllText($targetMetadataPath) | ConvertFrom-Json
    $targetExists = [bool]$target.before.exists
    $targetText = ''
    if ($targetExists) {
        $beforeFile = Join-Path $targetFolder 'config.before.toml'
        if (-not (Test-Path -LiteralPath $beforeFile -PathType Leaf)) { throw 'The snapshot is missing config.before.toml.' }
        $targetText = [IO.File]::ReadAllText($beforeFile)
    }

    $currentExists = Test-Path -LiteralPath $path -PathType Leaf
    $currentText = $(if ($currentExists) { [IO.File]::ReadAllText($path) } else { '' })
    $codex = Get-RecommendedCodexInfo -CodexPath $CodexPath
    if (-not $codex -or -not $codex.supports_system_proxy) { throw 'A verified Codex engine is required before restoring a snapshot.' }
    $restoreSnapshot = New-ConfigSnapshot -ConfigPath $path -Operation 'restore' -BeforeExists $currentExists -BeforeText $currentText -AfterExists $targetExists -AfterText $targetText -CodexInfo $codex -ProxyInfo (Get-WindowsSystemProxy) -TargetSnapshotId $SnapshotId
    try {
        Restore-ConfigContent -Path $path -Exists $targetExists -Text $targetText
        $status = Get-CodexConfigStatus -ConfigPath $path
        $expectedState = [string]$target.before.feature_state
        if ($status.feature_state -ne $expectedState) { throw ("Restored config state is {0}, expected {1}." -f $status.feature_state, $expectedState) }
        Test-CodexExpectedFeature -CodexInfo $codex -ExpectedState $expectedState
        Update-SnapshotResult -Snapshot $restoreSnapshot -Result 'success' -ErrorText $null
        return [pscustomobject]@{ restored = $true; source_snapshot_id = $SnapshotId; safety_snapshot_id = $restoreSnapshot.id; config = $status; message = 'Snapshot restored and verified.' }
    } catch {
        Restore-ConfigContent -Path $path -Exists $currentExists -Text $currentText
        Update-SnapshotResult -Snapshot $restoreSnapshot -Result 'rolled_back' -ErrorText $_.Exception.Message
        throw ("Snapshot restore failed and the current config was restored. {0}" -f $_.Exception.Message)
    }
}

Export-ModuleMember -Function @(
    'Get-CodexConfigPath',
    'Get-FeatureStateFromText',
    'Enable-SystemProxyFeatureText',
    'Get-CodexConfigStatus',
    'Get-CodexInstallations',
    'Get-CodexEngineInfo',
    'Get-WindowsSystemProxy',
    'Test-ProxyInput',
    'Get-ConfigSnapshots',
    'Get-DetectionReport',
    'Get-RepairPlan',
    'Invoke-CodexProxyRepair',
    'Restore-CodexProxySnapshot'
)
