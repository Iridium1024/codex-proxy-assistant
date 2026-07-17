@echo off
setlocal
set "CODEX_VPN_REPAIR_SELF=%~f0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$raw=[IO.File]::ReadAllText($env:CODEX_VPN_REPAIR_SELF); $parts=$raw -split '(?m)^:POWERSHELL_PAYLOAD\r?$'; if($parts.Count -lt 2){Write-Error 'Embedded PowerShell payload is missing.'; exit 90}; & ([ScriptBlock]::Create($parts[$parts.Count-1])) @args" %*
set "CODEX_VPN_REPAIR_EXIT=%ERRORLEVEL%"
endlocal & exit /b %CODEX_VPN_REPAIR_EXIT%

:POWERSHELL_PAYLOAD
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandLineArgs
)

# Codex VPN repair helper for Windows 10/11.
# This file uses only Windows PowerShell 5.1-compatible syntax and built-in APIs.
# It never changes Windows proxy settings, certificates, firewall rules, or VPN files.

$ErrorActionPreference = 'Stop'
$Action = 'Repair'
$DryRun = $false
$NoPause = $false
$ExitCode = 0

foreach ($argument in $CommandLineArgs) {
    switch ($argument.ToLowerInvariant()) {
        'status'        { $Action = 'Status' }
        '--status'      { $Action = 'Status' }
        '/status'       { $Action = 'Status' }
        'repair'        { $Action = 'Repair' }
        '--repair'      { $Action = 'Repair' }
        '/repair'       { $Action = 'Repair' }
        'restore'       { $Action = 'Restore' }
        '--restore'     { $Action = 'Restore' }
        '/restore'      { $Action = 'Restore' }
        '--dry-run'     { $DryRun = $true }
        '/dry-run'      { $DryRun = $true }
        '-whatif'       { $DryRun = $true }
        '--no-pause'    { $NoPause = $true }
        '/no-pause'     { $NoPause = $true }
        default {
            Write-Host "Unknown argument: $argument" -ForegroundColor Red
            Write-Host 'Usage: codex-vpn-repair.cmd [status|repair|restore] [--dry-run] [--no-pause]'
            $ExitCode = 64
        }
    }
}

function Write-Heading {
    param([string]$Text)
    Write-Host ''
    Write-Host ("== {0} ==" -f $Text) -ForegroundColor Cyan
}

function Write-Good {
    param([string]$Text)
    Write-Host ("[OK] {0}" -f $Text) -ForegroundColor Green
}

function Write-Warn {
    param([string]$Text)
    Write-Host ("[WARN] {0}" -f $Text) -ForegroundColor Yellow
}

function Write-Bad {
    param([string]$Text)
    Write-Host ("[ERROR] {0}" -f $Text) -ForegroundColor Red
}

function Add-Installation {
    param(
        [System.Collections.ArrayList]$List,
        [hashtable]$Seen,
        [string]$Path,
        [string]$Source,
        [bool]$Runnable
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    try { $fullPath = [IO.Path]::GetFullPath($expanded) } catch { return }
    $key = $fullPath.ToLowerInvariant()
    if ($Seen.ContainsKey($key)) { return }
    if (-not (Test-Path -LiteralPath $fullPath)) { return }

    $Seen[$key] = $true
    [void]$List.Add([pscustomobject]@{
        Path = $fullPath
        Source = $Source
        Runnable = $Runnable
    })
}

function Get-CodexInstallations {
    $items = New-Object System.Collections.ArrayList
    $seen = @{}

    try {
        $commands = @(Get-Command codex.cmd, codex.exe, codex -All -ErrorAction SilentlyContinue)
        foreach ($command in $commands) {
            $path = $command.Path
            if ([string]::IsNullOrWhiteSpace($path)) { $path = $command.Source }
            $extension = [IO.Path]::GetExtension([string]$path)
            if ($extension -in @('.cmd', '.bat', '.exe')) {
                Add-Installation $items $seen $path 'PATH' $true
            }
        }
    } catch {
        Write-Warn ("Could not inspect PATH commands: {0}" -f $_.Exception.Message)
    }

    $commonPaths = @()
    if ($env:APPDATA) {
        $commonPaths += (Join-Path $env:APPDATA 'npm\codex.cmd')
    }
    if ($env:LOCALAPPDATA) {
        $commonPaths += (Join-Path $env:LOCALAPPDATA 'Programs\Codex\resources\codex.exe')
        $commonPaths += (Join-Path $env:LOCALAPPDATA 'Programs\Codex\codex.exe')
    }
    if ($env:ProgramFiles) {
        $commonPaths += (Join-Path $env:ProgramFiles 'Codex\resources\codex.exe')
        $commonPaths += (Join-Path $env:ProgramFiles 'Codex\codex.exe')
    }
    foreach ($path in $commonPaths) {
        Add-Installation $items $seen $path 'common path' $true
    }

    try {
        $packages = @(Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue)
        foreach ($package in $packages) {
            $engine = Join-Path $package.InstallLocation 'app\resources\codex.exe'
            Add-Installation $items $seen $engine ("Desktop package {0}" -f $package.Version) $true
            Add-Installation $items $seen $package.InstallLocation ("Desktop package {0}" -f $package.Version) $false
        }
    } catch {
        Write-Warn ("Could not inspect the Desktop package: {0}" -f $_.Exception.Message)
    }

    try {
        $processes = @(Get-CimInstance Win32_Process -Filter "Name='codex.exe'" -ErrorAction SilentlyContinue)
        foreach ($process in $processes) {
            Add-Installation $items $seen $process.ExecutablePath 'running process' $true
        }
    } catch {
        # Process inspection may be restricted; installation detection still has other paths.
    }

    return @($items)
}

function Get-CodexEngineInfo {
    param([string]$Path)

    $version = 'unknown'
    $supportsFeature = $false
    $featureEnabled = $false
    $errorText = $null

    $previousErrorAction = $ErrorActionPreference
    try {
        # Windows PowerShell turns a native program's stderr into ErrorRecord objects.
        # Codex may print a harmless warning there, so capture it without aborting.
        $ErrorActionPreference = 'Continue'
        $versionOutput = @(& $Path --version 2>&1)
        $versionLine = @($versionOutput | Where-Object { [string]$_ -match '^codex-cli\s+' } | Select-Object -First 1)
        if ($versionLine.Count -gt 0) {
            $version = ([string]$versionLine[0]).Trim()
        }

        $featureOutput = @(& $Path features list 2>&1)
        $featureLine = @($featureOutput | Where-Object { [string]$_ -match '^respect_system_proxy\s+' } | Select-Object -First 1)
        if ($featureLine.Count -gt 0) {
            $supportsFeature = $true
            $featureEnabled = ([string]$featureLine[0] -match '\s+true\s*$')
        }
    } catch {
        $errorText = $_.Exception.Message
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }

    return [pscustomobject]@{
        Path = $Path
        Version = $version
        SupportsFeature = $supportsFeature
        FeatureEnabled = $featureEnabled
        Error = $errorText
    }
}

function Get-SystemProxyInfo {
    $result = [ordered]@{
        Enabled = $false
        ProxyServer = $null
        AutoConfigUrl = $null
        AutoDetect = $false
        Host = $null
        Port = $null
        DisplayEndpoint = $null
        TcpReachable = $null
    }

    try {
        $settings = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        $result.Enabled = ([int]$settings.ProxyEnable -eq 1)
        $result.ProxyServer = [string]$settings.ProxyServer
        $result.AutoConfigUrl = [string]$settings.AutoConfigURL
        $result.AutoDetect = ([int]$settings.AutoDetect -eq 1)
    } catch {
        Write-Warn ("Could not read Windows user proxy settings: {0}" -f $_.Exception.Message)
    }

    $endpoint = $null
    if (-not [string]::IsNullOrWhiteSpace($result.ProxyServer)) {
        $entries = @{}
        foreach ($piece in ($result.ProxyServer -split ';')) {
            $trimmed = $piece.Trim()
            if ($trimmed -match '^([^=]+)=(.+)$') {
                $entries[$matches[1].ToLowerInvariant()] = $matches[2].Trim()
            } elseif (-not $endpoint) {
                $endpoint = $trimmed
            }
        }
        foreach ($name in @('https', 'http', 'socks')) {
            if ($entries.ContainsKey($name)) {
                $endpoint = $entries[$name]
                break
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($endpoint)) {
        try {
            $uriText = $endpoint
            if ($uriText -notmatch '^[a-z][a-z0-9+.-]*://') {
                $uriText = 'http://' + $uriText
            }
            $uri = New-Object Uri($uriText)
            $result.Host = $uri.Host
            $result.Port = $uri.Port
            $result.DisplayEndpoint = ("{0}://{1}:{2}" -f $uri.Scheme, $uri.Host, $uri.Port)
        } catch {
            Write-Warn 'Windows has a proxy value, but its host and port could not be parsed.'
        }
    }

    return [pscustomobject]$result
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
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false)) {
            return $false
        }
        $client.EndConnect($async)
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Get-ConfigPath {
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        return (Join-Path $env:CODEX_HOME 'config.toml')
    }
    $userProfile = [Environment]::GetFolderPath('UserProfile')
    return (Join-Path (Join-Path $userProfile '.codex') 'config.toml')
}

function Get-FeatureState {
    param([string]$Text)

    $lines = @([regex]::Split($Text, '\r?\n'))
    $sectionIndexes = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[features\]\s*(?:#.*)?$') {
            [void]$sectionIndexes.Add($i)
        }
    }
    if ($sectionIndexes.Count -gt 1) { return 'invalid-duplicate-section' }
    if ($sectionIndexes.Count -eq 0) { return 'missing' }

    $start = [int]$sectionIndexes[0] + 1
    $end = $lines.Count
    for ($i = $start; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[[^\]]+\]\s*(?:#.*)?$') {
            $end = $i
            break
        }
    }

    $matchesFound = @()
    for ($i = $start; $i -lt $end; $i++) {
        if ($lines[$i] -match '^\s*respect_system_proxy\s*=\s*(true|false)\s*(?:#.*)?$') {
            $matchesFound += $matches[1].ToLowerInvariant()
        }
    }
    if ($matchesFound.Count -gt 1) { return 'invalid-duplicate-key' }
    if ($matchesFound.Count -eq 0) { return 'missing' }
    return $matchesFound[0]
}

function Enable-SystemProxyFeature {
    param([string]$Text)

    $newline = "`r`n"
    if ($Text -notmatch "`r`n" -and $Text -match "`n") { $newline = "`n" }

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in [regex]::Split($Text, '\r?\n')) { [void]$lines.Add($line) }
    if ($Text.Length -eq 0) { $lines.Clear() }

    $sectionIndexes = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[features\]\s*(?:#.*)?$') { $sectionIndexes += $i }
    }
    if ($sectionIndexes.Count -gt 1) { throw 'config.toml contains more than one [features] section.' }

    if ($sectionIndexes.Count -eq 0) {
        if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
            $lines.Add('')
        }
        $lines.Add('[features]')
        $lines.Add('respect_system_proxy = true')
        return (($lines -join $newline).TrimEnd("`r", "`n") + $newline)
    }

    $start = [int]$sectionIndexes[0] + 1
    $end = $lines.Count
    for ($i = $start; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[[^\]]+\]\s*(?:#.*)?$') {
            $end = $i
            break
        }
    }

    $keyIndexes = @()
    for ($i = $start; $i -lt $end; $i++) {
        if ($lines[$i] -match '^\s*respect_system_proxy\s*=') { $keyIndexes += $i }
    }
    if ($keyIndexes.Count -gt 1) { throw 'The [features] section contains duplicate respect_system_proxy keys.' }

    if ($keyIndexes.Count -eq 1) {
        $index = [int]$keyIndexes[0]
        if ($lines[$index] -notmatch '^(\s*respect_system_proxy\s*=\s*)(true|false)(\s*(?:#.*)?)$') {
            throw 'respect_system_proxy exists but is not a simple true/false value.'
        }
        $lines[$index] = $matches[1] + 'true' + $matches[3]
    } else {
        $lines.Insert($end, 'respect_system_proxy = true')
    }

    return (($lines -join $newline).TrimEnd("`r", "`n") + $newline)
}

function Write-FileAtomically {
    param(
        [string]$Path,
        [string]$Content
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }
    $temporary = Join-Path $directory ('.codex-vpn-repair-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $encoding = New-Object Text.UTF8Encoding($false)
    try {
        [IO.File]::WriteAllText($temporary, $Content, $encoding)
        if (Test-Path -LiteralPath $Path) {
            [IO.File]::Replace($temporary, $Path, $null, $true)
        } else {
            [IO.File]::Move($temporary, $Path)
        }
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Backup-Config {
    param([string]$ConfigPath)

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    if (Test-Path -LiteralPath $ConfigPath) {
        $backup = $ConfigPath + '.bak.' + $stamp
        Copy-Item -LiteralPath $ConfigPath -Destination $backup -Force
        return $backup
    }

    $backup = $ConfigPath + '.bak.' + $stamp + '.absent'
    $directory = Split-Path -Parent $ConfigPath
    if (-not (Test-Path -LiteralPath $directory)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }
    [IO.File]::WriteAllText($backup, '', (New-Object Text.UTF8Encoding($false)))
    return $backup
}

function Restore-LatestConfig {
    param(
        [string]$ConfigPath,
        [bool]$Preview
    )

    $directory = Split-Path -Parent $ConfigPath
    $name = Split-Path -Leaf $ConfigPath
    $backups = @()
    if (Test-Path -LiteralPath $directory) {
        $backups = @(Get-ChildItem -LiteralPath $directory -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like ($name + '.bak.*') } |
            Sort-Object LastWriteTimeUtc -Descending)
    }
    if ($backups.Count -eq 0) {
        throw 'No config.toml backup created by this tool was found.'
    }

    $latest = $backups[0]
    if ($Preview) {
        Write-Host ("[DRY-RUN] Would restore: {0}" -f $latest.FullName)
        return
    }

    if ($latest.Name.EndsWith('.absent', [StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $ConfigPath) {
            $beforeRestore = $ConfigPath + '.before-restore.' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
            Copy-Item -LiteralPath $ConfigPath -Destination $beforeRestore -Force
            Remove-Item -LiteralPath $ConfigPath -Force
            Write-Good ("Restored the original state (config.toml did not exist). Saved current file as {0}" -f $beforeRestore)
        } else {
            Write-Good 'config.toml is already absent, matching the latest backup.'
        }
    } else {
        if (Test-Path -LiteralPath $ConfigPath) {
            $beforeRestore = $ConfigPath + '.before-restore.' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
            Copy-Item -LiteralPath $ConfigPath -Destination $beforeRestore -Force
            Write-Host ("Saved the current config before restoring: {0}" -f $beforeRestore)
        }
        Copy-Item -LiteralPath $latest.FullName -Destination $ConfigPath -Force
        Write-Good ("Restored: {0}" -f $latest.FullName)
    }
}

function Test-FeatureAfterWrite {
    param([object[]]$EngineInfos)

    foreach ($engine in $EngineInfos) {
        if (-not $engine.SupportsFeature) { continue }
        $previousErrorAction = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $output = @(& $engine.Path features list 2>&1)
        } finally {
            $ErrorActionPreference = $previousErrorAction
        }
        $line = @($output | Where-Object { [string]$_ -match '^respect_system_proxy\s+' } | Select-Object -First 1)
        if ($line.Count -eq 0 -or [string]$line[0] -notmatch '\s+true\s*$') {
            throw ("Codex did not confirm the setting after the write: {0}" -f $engine.Path)
        }
    }
}

try {
    if ($ExitCode -ne 0) { throw 'Invalid command line.' }

    Write-Host 'Codex VPN / system-proxy repair' -ForegroundColor White
    Write-Host ("Action: {0}{1}" -f $Action, $(if ($DryRun) { ' (dry run)' } else { '' }))

    $configPath = Get-ConfigPath

    if ($Action -eq 'Restore') {
        Write-Heading 'Restore'
        Write-Host ("Config: {0}" -f $configPath)
        Restore-LatestConfig $configPath $DryRun
        $ExitCode = 0
    } else {
        Write-Heading 'Codex installations'
        $installations = @(Get-CodexInstallations)
        if ($installations.Count -eq 0) {
            Write-Bad 'No Codex CLI or Desktop installation was found in PATH, common folders, AppX packages, or running processes.'
            $ExitCode = 2
        } else {
            foreach ($installation in $installations) {
                Write-Host ("- [{0}] {1}" -f $installation.Source, $installation.Path)
            }
        }

        $engineInfos = @()
        foreach ($installation in @($installations | Where-Object { $_.Runnable })) {
            $engineInfos += Get-CodexEngineInfo $installation.Path
        }
        foreach ($engine in $engineInfos) {
            if ($engine.SupportsFeature) {
                Write-Good ("{0} supports respect_system_proxy ({1})." -f $engine.Path, $engine.Version)
            } else {
                Write-Warn ("Could not verify respect_system_proxy support in {0} ({1})." -f $engine.Path, $engine.Version)
            }
        }

        Write-Heading 'Windows proxy'
        $proxy = Get-SystemProxyInfo
        if ($proxy.Enabled) {
            Write-Good 'The Windows user proxy is enabled.'
        } elseif (-not [string]::IsNullOrWhiteSpace($proxy.AutoConfigUrl) -or $proxy.AutoDetect) {
            Write-Good 'Windows proxy auto-configuration is enabled.'
        } else {
            Write-Warn 'No enabled Windows user proxy was found. Turn on System Proxy in the VPN/proxy app, then run this tool again.'
            if ($ExitCode -eq 0) { $ExitCode = 2 }
        }

        if ($proxy.DisplayEndpoint) {
            Write-Host ("Proxy endpoint: {0}" -f $proxy.DisplayEndpoint)
            $proxy.TcpReachable = Test-TcpEndpoint $proxy.Host ([int]$proxy.Port)
            if ($proxy.TcpReachable) {
                Write-Good 'The proxy TCP port is reachable.'
            } else {
                Write-Bad 'The configured proxy TCP port is not reachable. Start the VPN/proxy app or correct its local port first.'
                if ($ExitCode -eq 0) { $ExitCode = 2 }
            }
        } elseif (-not [string]::IsNullOrWhiteSpace($proxy.AutoConfigUrl)) {
            Write-Host 'A PAC URL is configured. Endpoint testing is skipped; Codex will resolve the system proxy at runtime.'
        } elseif ($proxy.AutoDetect) {
            Write-Host 'WPAD/automatic detection is configured. Endpoint testing is skipped.'
        }

        $proxyVariableNames = @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY') |
            Where-Object { -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_, 'Process')) }
        if ($proxyVariableNames.Count -gt 0) {
            Write-Host ("Current process proxy variables set (values hidden): {0}" -f ($proxyVariableNames -join ', '))
        } else {
            Write-Host 'Current process proxy variables: none (this is acceptable when system-proxy support is enabled).'
        }

        Write-Heading 'Codex configuration'
        Write-Host ("Config: {0}" -f $configPath)
        $configText = ''
        if (Test-Path -LiteralPath $configPath) {
            $configText = [IO.File]::ReadAllText($configPath)
        }
        $state = Get-FeatureState $configText
        Write-Host ("respect_system_proxy: {0}" -f $state)

        if ($Action -eq 'Status') {
            if ($state -eq 'true') { Write-Good 'Codex is configured to respect the system proxy.' }
            elseif ($ExitCode -eq 0) { Write-Warn 'Run this file without "status" to apply the repair.' }
        } elseif ($Action -eq 'Repair' -and $ExitCode -eq 0) {
            if ($state -like 'invalid-*') {
                throw ("The existing config cannot be changed safely: {0}" -f $state)
            }

            $supported = @($engineInfos | Where-Object { $_.SupportsFeature })
            $verifiedUnsupported = @($engineInfos | Where-Object { -not $_.SupportsFeature -and [string]::IsNullOrWhiteSpace($_.Error) })
            if ($state -eq 'true') {
                Write-Good 'No change is needed. The setting is already enabled.'
            } elseif ($supported.Count -eq 0 -or $verifiedUnsupported.Count -gt 0) {
                Write-Bad 'Repair stopped: at least one runnable Codex engine must confirm support, and none may explicitly report the feature missing. Update Codex, then retry.'
                $ExitCode = 3
            } else {
                $newText = Enable-SystemProxyFeature $configText
                if ($DryRun) {
                    Write-Host '[DRY-RUN] Would back up config.toml and set [features] respect_system_proxy = true.'
                } else {
                    $backup = Backup-Config $configPath
                    try {
                        Write-FileAtomically $configPath $newText
                        if ((Get-FeatureState ([IO.File]::ReadAllText($configPath))) -ne 'true') {
                            throw 'The written config did not pass local verification.'
                        }
                        Test-FeatureAfterWrite $engineInfos
                        Write-Good 'Enabled [features] respect_system_proxy = true.'
                        Write-Host ("Backup: {0}" -f $backup)
                    } catch {
                        if ($backup.EndsWith('.absent', [StringComparison]::OrdinalIgnoreCase)) {
                            if (Test-Path -LiteralPath $configPath) { Remove-Item -LiteralPath $configPath -Force }
                        } else {
                            Copy-Item -LiteralPath $backup -Destination $configPath -Force
                        }
                        throw ("Verification failed; the original config was restored. {0}" -f $_.Exception.Message)
                    }
                }
            }
        }

        if ($Action -eq 'Repair' -and $ExitCode -eq 0) {
            Write-Heading 'Next step'
            Write-Host 'Fully exit and restart Codex Desktop/CLI so new processes read the setting.'
            Write-Host 'This tool intentionally does not terminate a running task.'
        }
    }
} catch {
    if ($ExitCode -eq 0) { $ExitCode = 1 }
    Write-Bad $_.Exception.Message
} finally {
    if (-not $NoPause) {
        Write-Host ''
        [void](Read-Host 'Press Enter to close')
    }
}

exit $ExitCode
