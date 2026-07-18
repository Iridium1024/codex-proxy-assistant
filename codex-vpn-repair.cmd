@echo off
setlocal
set "CODEX_VPN_REPAIR_SELF=%~f0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$raw=[IO.File]::ReadAllText($env:CODEX_VPN_REPAIR_SELF); $parts=$raw -split '(?m)^:POWERSHELL_PAYLOAD\r?$'; if($parts.Count -lt 2){Write-Error 'Embedded PowerShell payload is missing.'; exit 90}; & ([ScriptBlock]::Create($parts[$parts.Count-1])) @args" %*
set "CODEX_VPN_REPAIR_EXIT=%ERRORLEVEL%"
endlocal & exit /b %CODEX_VPN_REPAIR_EXIT%

:POWERSHELL_PAYLOAD
# GENERATED FILE. Edit powershell\CodexProxy.Core.psm1 or CodexProxy.Standalone.ps1.
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

function ConvertTo-NativeArgument {
    param([string]$Value)

    if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ([regex]::Replace($Value, '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}

function Stop-ProcessTree {
    param([int]$ProcessId)

    try {
        & "$env:SystemRoot\System32\taskkill.exe" /PID $ProcessId /T /F *> $null
    } catch {
        try { Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue } catch { }
    }
}

function Invoke-NativeCommandWithTimeout {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$Arguments = @(),
        [int]$TimeoutMilliseconds = 5000
    )

    $result = [ordered]@{
        started = $false
        timed_out = $false
        exit_code = $null
        stdout = ''
        stderr = ''
        error_class = $null
        error = $null
    }
    try {
        $expanded = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))
        $startInfo = New-Object Diagnostics.ProcessStartInfo
        $extension = [IO.Path]::GetExtension($expanded).ToLowerInvariant()
        if ($extension -in @('.cmd', '.bat')) {
            $startInfo.FileName = $(if ($env:ComSpec) { $env:ComSpec } else { 'cmd.exe' })
            $argumentText = (($Arguments | ForEach-Object { ConvertTo-NativeArgument -Value ([string]$_) }) -join ' ')
            $startInfo.Arguments = ('/d /s /c call "{0}" {1}' -f $expanded.Replace('"', '""'), $argumentText).TrimEnd()
        } else {
            $startInfo.FileName = $expanded
            $startInfo.Arguments = (($Arguments | ForEach-Object { ConvertTo-NativeArgument -Value ([string]$_) }) -join ' ')
        }
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.WorkingDirectory = Split-Path -Parent $expanded
        $startInfo.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
        $startInfo.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)

        $process = New-Object Diagnostics.Process
        $process.StartInfo = $startInfo
        try {
            if (-not $process.Start()) { throw 'The process did not start.' }
            $result.started = $true
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit($TimeoutMilliseconds)) {
                $result.timed_out = $true
                $result.error_class = 'probe_timeout'
                $result.error = ('The command did not finish within {0} ms.' -f $TimeoutMilliseconds)
                Stop-ProcessTree -ProcessId $process.Id
                [void]$process.WaitForExit(2000)
            }
            if ($process.HasExited) { $result.exit_code = $process.ExitCode }
            try { $result.stdout = [string]$stdoutTask.Result } catch { }
            try { $result.stderr = [string]$stderrTask.Result } catch { }
            if (-not $result.timed_out -and $result.exit_code -ne 0) {
                $result.error_class = 'nonzero_exit'
                $result.error = ([string]$result.stderr).Trim()
                if ([string]::IsNullOrWhiteSpace($result.error)) { $result.error = ('Command exited with code {0}.' -f $result.exit_code) }
            }
        } finally {
            $process.Dispose()
        }
    } catch {
        $result.error_class = 'launch_failed'
        $result.error = $_.Exception.Message
    }
    return [pscustomobject]$result
}

function Add-CodexInstallation {
    param(
        [System.Collections.ArrayList]$List,
        [hashtable]$Seen,
        [string]$Path,
        [string]$Source,
        [string]$Kind,
        [bool]$Runnable,
        [bool]$Trusted = $false,
        [int]$Priority = 100,
        [string]$PackageVersion
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
        trusted = $Trusted
        priority = $Priority
        package_version = $PackageVersion
    })
}

function Get-CodexInstallations {
    $items = New-Object System.Collections.ArrayList
    $seen = @{}

    try {
        foreach ($package in @(Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue | Sort-Object Version -Descending)) {
            Add-CodexInstallation $items $seen (Join-Path $package.InstallLocation 'app\resources\codex.exe') 'appx' 'desktop' $true $true 10 ([string]$package.Version)
        }
    } catch { }

    $common = @()
    if ($env:LOCALAPPDATA) {
        $common += (Join-Path $env:LOCALAPPDATA 'Programs\Codex\resources\codex.exe')
        $common += (Join-Path $env:LOCALAPPDATA 'Programs\Codex\codex.exe')
    }
    if ($env:ProgramFiles) {
        $common += (Join-Path $env:ProgramFiles 'Codex\resources\codex.exe')
        $common += (Join-Path $env:ProgramFiles 'Codex\codex.exe')
    }
    foreach ($path in $common) { Add-CodexInstallation $items $seen $path 'standard_path' 'desktop' $true $true 20 $null }

    if ($env:APPDATA) { Add-CodexInstallation $items $seen (Join-Path $env:APPDATA 'npm\codex.cmd') 'npm' 'cli' $true $true 40 $null }

    try {
        foreach ($process in @(Get-CimInstance Win32_Process -Filter "Name='codex.exe'" -ErrorAction SilentlyContinue)) {
            $processKind = $(if ([string]$process.ExecutablePath -match '(?i)WindowsApps\\OpenAI\.Codex_|\\Programs\\Codex\\') { 'desktop' } else { 'cli' })
            Add-CodexInstallation $items $seen $process.ExecutablePath 'running_process' $processKind $true $true 30 $null
        }
    } catch { }

    try {
        foreach ($command in @(Get-Command codex.cmd, codex.exe, codex -All -ErrorAction SilentlyContinue)) {
            $path = $command.Path
            if ([string]::IsNullOrWhiteSpace($path)) { $path = $command.Source }
            if ([IO.Path]::GetExtension([string]$path) -in @('.cmd', '.bat', '.exe')) {
                $isNpm = ([string]$path -match '(?i)\\AppData\\Roaming\\npm\\codex\.(cmd|bat)$')
                $isDesktop = ([string]$path -match '(?i)WindowsApps\\OpenAI\.Codex_|\\Programs\\Codex\\')
                $source = $(if ($isNpm) { 'npm' } else { 'path' })
                $kind = $(if ($isDesktop) { 'desktop' } else { 'cli' })
                Add-CodexInstallation $items $seen $path $source $kind $true ([bool]($isNpm -or $isDesktop)) $(if ($isNpm) { 40 } else { 80 }) $null
            }
        }
    } catch { }
    return @($items)
}

function Get-CodexEngineInfo {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateSet('desktop', 'cli')][string]$Kind = 'cli',
        [string]$Source = 'user_selected',
        [string]$PackageVersion,
        [int]$TimeoutMilliseconds = 5000
    )

    try { $expanded = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)) } catch { $expanded = $Path }
    if ($Kind -eq 'cli' -and $expanded -match '(?i)WindowsApps\\OpenAI\.Codex_|\\Programs\\Codex\\') { $Kind = 'desktop' }
    if (-not (Test-Path -LiteralPath $expanded -PathType Leaf)) {
        return [pscustomobject]@{
            path = $expanded; kind = $Kind; source = $Source; package_version = $PackageVersion
            exists = $false; runnable = $false; version = 'unknown'; supports_system_proxy = $false
            feature_enabled = $false; timed_out = $false; error_class = 'path_missing'; error = 'File not found.'
        }
    }

    $version = 'unknown'
    $supports = $false
    $enabled = $false
    $errorText = $null
    $errorClass = $null
    $timedOut = $false
    try {
        $versionProbe = Invoke-NativeCommandWithTimeout -Path $expanded -Arguments @('--version') -TimeoutMilliseconds $TimeoutMilliseconds
        if ($versionProbe.timed_out) {
            $timedOut = $true
            $errorClass = 'probe_timeout'
            $errorText = 'Codex version detection timed out.'
        } elseif (-not $versionProbe.started) {
            $errorClass = [string]$versionProbe.error_class
            $errorText = [string]$versionProbe.error
        }
        $versionOutput = @(([string]$versionProbe.stdout -split '\r?\n') + ([string]$versionProbe.stderr -split '\r?\n'))
        $versionLine = @($versionOutput | Where-Object { [string]$_ -match '^codex-cli\s+' } | Select-Object -First 1)
        if ($versionLine.Count -gt 0) { $version = ([string]$versionLine[0]).Trim() }
        $featureOutput = @()
        if (-not $timedOut -and $versionProbe.started) {
            $featureProbe = Invoke-NativeCommandWithTimeout -Path $expanded -Arguments @('features', 'list') -TimeoutMilliseconds $TimeoutMilliseconds
            if ($featureProbe.timed_out) {
                $timedOut = $true
                $errorClass = 'probe_timeout'
                $errorText = 'Codex feature detection timed out.'
            }
            $featureOutput = @(([string]$featureProbe.stdout -split '\r?\n') + ([string]$featureProbe.stderr -split '\r?\n'))
            $featureLine = @($featureOutput | Where-Object { [string]$_ -match '^respect_system_proxy\s+' } | Select-Object -First 1)
            if ($featureLine.Count -gt 0) {
                $supports = $true
                $enabled = ([string]$featureLine[0] -match '\s+true\s*$')
            } elseif ($featureProbe.error_class) {
                $errorClass = [string]$featureProbe.error_class
                $errorText = [string]$featureProbe.error
            }
        }
        if (-not $timedOut -and $version -eq 'unknown' -and -not $supports -and [string]::IsNullOrWhiteSpace($errorText)) {
            $errorText = (($versionOutput + $featureOutput | ForEach-Object { [string]$_ }) -join ' ').Trim()
            if ([string]::IsNullOrWhiteSpace($errorText)) { $errorText = 'The executable could not be verified.' }
            if (-not $errorClass) { $errorClass = 'unverified_executable' }
        }
    } catch {
        $errorText = $_.Exception.Message
        $errorClass = 'probe_failed'
    }
    return [pscustomobject]@{
        path = $expanded
        kind = $Kind
        source = $Source
        package_version = $PackageVersion
        exists = $true
        runnable = [bool](-not $timedOut -and ($supports -or $version -ne 'unknown'))
        version = $version
        supports_system_proxy = $supports
        feature_enabled = $enabled
        timed_out = $timedOut
        error_class = $errorClass
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
        $scheme = $uri.Scheme.ToLowerInvariant()
        if ($scheme -notin @('http', 'https', 'socks5', 'socks5h')) {
            return [pscustomobject]@{
                valid = $false; scheme = $scheme; host = $uri.Host; port = [int]$uri.Port
                normalized = $null; display = $null; has_credentials = -not [string]::IsNullOrWhiteSpace($uri.UserInfo)
                persistent_supported = $false; error_class = 'unsupported_scheme'
                error = 'Only http, https, socks5, and socks5h proxy URLs are recognized.'
            }
        }
        $hostDisplay = $uri.Host
        if ($hostDisplay.Contains(':') -and -not $hostDisplay.StartsWith('[')) { $hostDisplay = '[' + $hostDisplay + ']' }
        return [pscustomobject]@{
            valid = $true
            scheme = $scheme
            host = $uri.Host
            port = [int]$uri.Port
            normalized = ("{0}://{1}:{2}" -f $scheme, $hostDisplay, $uri.Port)
            display = ("{0}://{1}:{2}" -f $scheme, $hostDisplay, $uri.Port)
            has_credentials = -not [string]::IsNullOrWhiteSpace($uri.UserInfo)
            persistent_supported = ($scheme -in @('http', 'https'))
            error_class = $null
            error = $null
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

function Test-ProxyRoute {
    param(
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [string]$ProbeUrl = 'https://api.openai.com/',
        [int]$TcpTimeoutMilliseconds = 1800,
        [int]$ConnectTimeoutSeconds = 5,
        [int]$MaxTimeSeconds = 12,
        [string]$CurlPath,
        [switch]$AllowInsecureProbe
    )

    $parsed = ConvertTo-ProxyEndpoint -Endpoint $Endpoint
    if (-not $parsed) {
        return [pscustomobject]@{
            valid = $false; normalized = $null; display_endpoint = $null; scheme = $null; host = $null; port = $null
            persistent_supported = $false; has_credentials = $false; port_state = 'INVALID'; tcp_reachable = $false
            https_probe_status = 'INVALID_PROXY'; https_reachable = $false; http_status = 0; curl_exit_code = $null
            error_class = 'invalid_proxy'; error = 'Proxy must be a host:port or a valid proxy URL.'
            next_step = 'Enter the HTTP or Mixed proxy port shown by the proxy application.'
        }
    }
    if (-not $parsed.valid) {
        return [pscustomobject]@{
            valid = $false; normalized = $null; display_endpoint = $null; scheme = $parsed.scheme; host = $parsed.host; port = $parsed.port
            persistent_supported = $false; has_credentials = $parsed.has_credentials; port_state = 'INVALID'; tcp_reachable = $false
            https_probe_status = 'UNSUPPORTED_SCHEME'; https_reachable = $false; http_status = 0; curl_exit_code = $null
            error_class = $parsed.error_class; error = $parsed.error
            next_step = 'Use an HTTP or Mixed proxy port. SOCKS is recognized only for limited temporary use.'
        }
    }
    if ($parsed.has_credentials) {
        return [pscustomobject]@{
            valid = $false; normalized = $parsed.normalized; display_endpoint = $parsed.display; scheme = $parsed.scheme; host = $parsed.host; port = $parsed.port
            persistent_supported = $parsed.persistent_supported; has_credentials = $true; port_state = 'NOT_TESTED'; tcp_reachable = $null
            https_probe_status = 'CREDENTIALS_REJECTED'; https_reachable = $false; http_status = 0; curl_exit_code = $null
            error_class = 'proxy_credentials_rejected'; error = 'Proxy URLs containing a user name or password are not accepted.'
            next_step = 'Use a local proxy endpoint that does not embed credentials in the URL.'
        }
    }

    $tcpOpen = Test-TcpEndpoint -HostName $parsed.host -Port $parsed.port -TimeoutMilliseconds $TcpTimeoutMilliseconds
    if (-not $tcpOpen) {
        return [pscustomobject]@{
            valid = $true; normalized = $parsed.normalized; display_endpoint = $parsed.display; scheme = $parsed.scheme; host = $parsed.host; port = $parsed.port
            persistent_supported = $parsed.persistent_supported; has_credentials = $false; port_state = 'PORT_CLOSED'; tcp_reachable = $false
            https_probe_status = 'NOT_RUN'; https_reachable = $false; http_status = 0; curl_exit_code = $null
            error_class = 'port_closed'; error = 'The proxy port is not reachable.'
            next_step = 'Start the proxy application or verify its HTTP or Mixed port, then retry.'
        }
    }

    $resolvedCurl = $CurlPath
    if ([string]::IsNullOrWhiteSpace($resolvedCurl)) {
        try {
            $curlCommand = Get-Command curl.exe -ErrorAction Stop | Select-Object -First 1
            $resolvedCurl = $(if ($curlCommand.Path) { $curlCommand.Path } else { $curlCommand.Source })
        } catch { $resolvedCurl = $null }
    }
    if ([string]::IsNullOrWhiteSpace($resolvedCurl) -or -not (Test-Path -LiteralPath $resolvedCurl -PathType Leaf)) {
        return [pscustomobject]@{
            valid = $true; normalized = $parsed.normalized; display_endpoint = $parsed.display; scheme = $parsed.scheme; host = $parsed.host; port = $parsed.port
            persistent_supported = $parsed.persistent_supported; has_credentials = $false; port_state = 'PORT_OPEN'; tcp_reachable = $true
            https_probe_status = 'NOT_TESTED_NO_CURL'; https_reachable = $null; http_status = 0; curl_exit_code = $null
            error_class = 'curl_unavailable'; error = 'curl.exe was not found, so HTTPS proxy validation was not completed.'
            next_step = 'Use a supported Windows 10 or Windows 11 installation with curl.exe, or verify the proxy manually.'
        }
    }

    $arguments = @(
        '--silent', '--show-error', '--output', 'NUL',
        '--connect-timeout', [string]$ConnectTimeoutSeconds,
        '--max-time', [string]$MaxTimeSeconds,
        '--proxy', $parsed.normalized,
        '--noproxy', '',
        '--write-out', 'HTTP_CODE:%{http_code} CONNECT_CODE:%{http_connect}',
        $ProbeUrl
    )
    if ($AllowInsecureProbe) { $arguments = @('--insecure') + $arguments }
    $curl = Invoke-NativeCommandWithTimeout -Path $resolvedCurl -Arguments $arguments -TimeoutMilliseconds (($MaxTimeSeconds + 3) * 1000)
    $usedSslNoRevoke = $false
    if ($curl.exit_code -eq 35 -and [string]$curl.stderr -match 'CRYPT_E_REVOCATION_OFFLINE') {
        $usedSslNoRevoke = $true
        $curl = Invoke-NativeCommandWithTimeout -Path $resolvedCurl -Arguments (@('--ssl-no-revoke') + $arguments) -TimeoutMilliseconds (($MaxTimeSeconds + 3) * 1000)
    }
    $httpStatus = 0
    if ([string]$curl.stdout -match 'HTTP_CODE:(\d{3})') { $httpStatus = [int]$matches[1] }
    $connectStatus = 0
    if ([string]$curl.stdout -match 'CONNECT_CODE:(\d{3})') { $connectStatus = [int]$matches[1] }
    if ($httpStatus -eq 0 -and $connectStatus -eq 407) { $httpStatus = 407 }
    $exitCode = $(if ($null -ne $curl.exit_code) { [int]$curl.exit_code } else { $null })
    $status = 'FAILED'
    $reachable = $false
    $errorClass = $null
    $errorText = ([string]$curl.stderr).Trim()
    $nextStep = 'Verify that the selected port is the HTTP or Mixed proxy port and that the current node can reach HTTPS sites.'
    if ($httpStatus -eq 407) {
        $status = 'PROXY_AUTH_REQUIRED'
        $errorClass = 'proxy_auth_required'
        $errorText = 'The proxy requires authentication (HTTP 407).'
        $nextStep = 'Use a local proxy endpoint without authentication or configure authentication in the proxy application.'
    } elseif ($httpStatus -ge 200 -and $httpStatus -le 499) {
        $status = 'HTTPS_OK'
        $reachable = $true
        $errorText = $null
        $nextStep = 'The proxy can reach an HTTPS endpoint.'
    } elseif ($curl.timed_out -or $exitCode -eq 28) {
        $status = 'TIMEOUT'
        $errorClass = 'proxy_timeout'
        $errorText = 'The HTTPS proxy test timed out.'
        $nextStep = 'Check the current proxy node and retry, or switch to another node.'
    } elseif ($exitCode -eq 5) {
        $errorClass = 'proxy_dns_failed'
        $nextStep = 'Check the proxy host name or use a local numeric address such as 127.0.0.1.'
    } elseif ($exitCode -eq 6) {
        $errorClass = 'target_dns_failed'
        $nextStep = 'Enable remote DNS through the proxy or switch to a working proxy node.'
    } elseif ($exitCode -eq 7) {
        $errorClass = 'proxy_connect_failed'
        $nextStep = 'Confirm that the proxy application is running and the selected port is correct.'
    } elseif ($exitCode -in @(35, 60)) {
        $errorClass = 'tls_failed'
        $nextStep = 'Check TLS interception, certificates, proxy rules, or switch to another node.'
    } elseif ($exitCode -in @(52, 55, 56)) {
        $errorClass = 'connection_reset'
        $nextStep = 'The connection was interrupted; verify the HTTP or Mixed port and switch proxy nodes if needed.'
    } elseif ($httpStatus -eq 0) {
        $errorClass = 'no_http_response'
    } else {
        $errorClass = 'curl_error'
    }
    if ([string]::IsNullOrWhiteSpace($errorText) -and -not $reachable) { $errorText = 'The HTTPS proxy test did not receive a usable HTTP response.' }
    return [pscustomobject]@{
        valid = $true; normalized = $parsed.normalized; display_endpoint = $parsed.display; scheme = $parsed.scheme; host = $parsed.host; port = $parsed.port
        persistent_supported = $parsed.persistent_supported; has_credentials = $false; port_state = 'PORT_OPEN'; tcp_reachable = $true
        https_probe_status = $status; https_reachable = $reachable; http_status = $httpStatus; curl_exit_code = $exitCode
        proxy_connect_status = $connectStatus; used_ssl_no_revoke = $usedSslNoRevoke
        error_class = $errorClass; error = $errorText; next_step = $nextStep
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
    if ($endpoint -and -not $endpoint.valid) { $endpoint = $null }
    $route = $null
    if ($endpoint) { $route = Test-ProxyRoute -Endpoint $endpoint.normalized }

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
        scheme = $(if ($endpoint) { $endpoint.scheme } else { $null })
        persistent_supported = $(if ($endpoint) { $endpoint.persistent_supported } else { $null })
        tcp_reachable = $(if ($route) { $route.tcp_reachable } else { $null })
        port_state = $(if ($route) { $route.port_state } else { 'NOT_TESTED' })
        https_probe_status = $(if ($route) { $route.https_probe_status } elseif ($source -in @('pac', 'wpad')) { 'NOT_TESTED_DYNAMIC_PROXY' } else { 'NOT_RUN' })
        https_reachable = $(if ($route) { $route.https_reachable } else { $null })
        http_status = $(if ($route) { $route.http_status } else { 0 })
        curl_exit_code = $(if ($route) { $route.curl_exit_code } else { $null })
        used_ssl_no_revoke = $(if ($route -and $route.PSObject.Properties['used_ssl_no_revoke']) { $route.used_ssl_no_revoke } else { $false })
        error_class = $(if ($route) { $route.error_class } else { $null })
        next_step = $(if ($route) { $route.next_step } elseif ($source -in @('pac', 'wpad')) { 'PAC or WPAD is detected, but the static endpoint test is not applicable. Codex will resolve it at runtime.' } else { 'Enable the Windows system proxy or configure a PAC/WPAD source.' })
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

    $route = Test-ProxyRoute -Endpoint $Endpoint -TcpTimeoutMilliseconds $TimeoutMilliseconds
    $system = Get-WindowsSystemProxy
    $matchesSystem = $false
    if ($route.valid -and $system.endpoint) {
        $systemParsed = ConvertTo-ProxyEndpoint -Endpoint $system.endpoint
        $matchesSystem = ($systemParsed -and $systemParsed.valid -and $systemParsed.host.Equals($route.host, [StringComparison]::OrdinalIgnoreCase) -and $systemParsed.port -eq $route.port)
    }
    $route | Add-Member -NotePropertyName matches_system -NotePropertyValue $matchesSystem -Force
    return $route
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
    param(
        [string]$CodexPath,
        [object[]]$InstallationsOverride,
        [int]$ProbeTimeoutMilliseconds = 5000
    )

    if (-not [string]::IsNullOrWhiteSpace($CodexPath)) {
        return Get-CodexEngineInfo -Path $CodexPath -Source 'user_selected' -TimeoutMilliseconds $ProbeTimeoutMilliseconds
    }
    if ($PSBoundParameters.ContainsKey('InstallationsOverride')) {
        $resolved = Resolve-CodexTargets -CodexPath $CodexPath -InstallationsOverride $InstallationsOverride -ProbeTimeoutMilliseconds $ProbeTimeoutMilliseconds
    } else {
        $resolved = Resolve-CodexTargets -CodexPath $CodexPath -ProbeTimeoutMilliseconds $ProbeTimeoutMilliseconds
    }
    return $resolved.recommended
}

function Resolve-CodexTargets {
    param(
        [string]$CodexPath,
        [object[]]$InstallationsOverride,
        [int]$ProbeTimeoutMilliseconds = 5000
    )

    $installations = @($(if ($PSBoundParameters.ContainsKey('InstallationsOverride')) { $InstallationsOverride } else { Get-CodexInstallations }))
    $explicit = -not [string]::IsNullOrWhiteSpace($CodexPath)
    if ($explicit) {
        $expanded = try { [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($CodexPath)) } catch { $CodexPath }
        $matching = @($installations | Where-Object {
            try { [IO.Path]::GetFullPath([string]$_.path).Equals($expanded, [StringComparison]::OrdinalIgnoreCase) } catch { $false }
        } | Select-Object -First 1)
        if ($matching.Count -gt 0) {
            $selected = $matching[0]
            $selected = [pscustomobject]@{
                path = $expanded; source = 'user_selected'; kind = [string]$selected.kind; runnable = $true
                trusted = $true; priority = 0; package_version = $selected.package_version
            }
        } else {
            $selectedKind = $(if ($expanded -match '(?i)WindowsApps\\OpenAI\.Codex_|\\Programs\\Codex\\') { 'desktop' } else { 'cli' })
            $selected = [pscustomobject]@{
                path = $expanded; source = 'user_selected'; kind = $selectedKind; runnable = $true
                trusted = $true; priority = 0; package_version = $null
            }
        }
        $installations = @($selected) + @($installations | Where-Object {
            try { -not [IO.Path]::GetFullPath([string]$_.path).Equals($expanded, [StringComparison]::OrdinalIgnoreCase) } catch { $true }
        })
    }

    $engines = @()
    foreach ($installation in @($installations | Where-Object { $_.runnable } | Sort-Object priority, source, path)) {
        $engines += Get-CodexEngineInfo -Path ([string]$installation.path) -Kind ([string]$installation.kind) -Source ([string]$installation.source) -PackageVersion ([string]$installation.package_version) -TimeoutMilliseconds $ProbeTimeoutMilliseconds
    }

    $recommended = $null
    if ($explicit) {
        $recommended = @($engines | Where-Object { $_.source -eq 'user_selected' } | Select-Object -First 1)
    } else {
        $desktop = @($engines | Where-Object { $_.kind -eq 'desktop' -and $_.runnable } | Select-Object -First 1)
        if ($desktop.Count -gt 0) {
            $recommended = $desktop
        } else {
            $trustedCli = @($engines | Where-Object { $_.kind -eq 'cli' -and $_.source -ne 'path' } | Sort-Object @{ Expression = { -not $_.supports_system_proxy } }, @{ Expression = { -not $_.runnable } } | Select-Object -First 1)
            if ($trustedCli.Count -gt 0) { $recommended = $trustedCli }
            else { $recommended = @($engines | Where-Object { $_.kind -eq 'cli' } | Sort-Object @{ Expression = { -not $_.supports_system_proxy } }, @{ Expression = { -not $_.runnable } } | Select-Object -First 1) }
        }
    }
    return [pscustomobject]@{
        installations = $installations
        engines = $engines
        recommended = $(if (@($recommended).Count -gt 0) { @($recommended)[0] } else { $null })
        explicit_selection = $explicit
        skipped = @($engines | Where-Object { $_.error_class -or $_.timed_out })
    }
}

function Get-DetectionReport {
    param(
        [string]$CodexPath,
        [string]$ConfigPath,
        [object[]]$InstallationsOverride,
        [object]$SystemProxyOverride,
        [int]$ProbeTimeoutMilliseconds = 5000
    )

    if ($PSBoundParameters.ContainsKey('InstallationsOverride')) {
        $resolved = Resolve-CodexTargets -CodexPath $CodexPath -InstallationsOverride $InstallationsOverride -ProbeTimeoutMilliseconds $ProbeTimeoutMilliseconds
    } else {
        $resolved = Resolve-CodexTargets -CodexPath $CodexPath -ProbeTimeoutMilliseconds $ProbeTimeoutMilliseconds
    }
    $recommended = $resolved.recommended
    return [pscustomobject]@{
        installations = $resolved.installations
        engines = $resolved.engines
        recommended_path = $(if ($recommended) { $recommended.path } else { $null })
        recommended_kind = $(if ($recommended) { $recommended.kind } else { $null })
        recommended_source = $(if ($recommended) { $recommended.source } else { $null })
        recommended = $recommended
        explicit_selection = $resolved.explicit_selection
        skipped = $resolved.skipped
        proxy = $(if ($SystemProxyOverride) { $SystemProxyOverride } else { Get-WindowsSystemProxy })
        config = Get-CodexConfigStatus -ConfigPath $ConfigPath
        snapshots = @(Get-ConfigSnapshots -ConfigPath $ConfigPath)
    }
}

function Get-RepairPlan {
    param(
        [string]$CodexPath,
        [string]$ProxyEndpoint,
        [string]$ConfigPath,
        [object]$CodexInfoOverride,
        [object]$SystemProxyOverride
    )

    $codex = $(if ($CodexInfoOverride) { $CodexInfoOverride } else { Get-RecommendedCodexInfo -CodexPath $CodexPath })
    $systemProxy = $(if ($SystemProxyOverride) { $SystemProxyOverride } else { Get-WindowsSystemProxy })
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
        if ($systemProxy.source -eq 'manual' -and $systemProxy.PSObject.Properties['persistent_supported'] -and $systemProxy.persistent_supported -ne $true) {
            [void]$errors.Add('The configured Windows proxy is not an HTTP or HTTPS proxy supported by persistent repair.')
        }
        if ($systemProxy.source -eq 'manual' -and $systemProxy.PSObject.Properties['https_reachable'] -and $systemProxy.https_reachable -ne $true) {
            [void]$errors.Add('The configured Windows proxy did not pass the HTTPS route test.')
        }
        if ($systemProxy.source -in @('pac', 'wpad')) {
            [void]$warnings.Add('PAC or WPAD is detected; static HTTPS endpoint validation is not available and Codex will resolve it at runtime.')
        }
        if ($proxyInput) {
            if (-not $proxyInput.valid -or -not $proxyInput.tcp_reachable) { [void]$errors.Add('The proxy entered in the UI is invalid or unreachable.') }
            elseif (-not $proxyInput.persistent_supported) { [void]$errors.Add('The proxy entered in the UI is not an HTTP or HTTPS proxy supported by persistent repair.') }
            elseif ($proxyInput.https_reachable -ne $true) { [void]$errors.Add('The proxy entered in the UI did not pass the HTTPS route test.') }
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
    $probe = Invoke-NativeCommandWithTimeout -Path $CodexInfo.path -Arguments @('features', 'list') -TimeoutMilliseconds 5000
    if ($probe.timed_out) { throw 'Codex feature verification timed out.' }
    if (-not $probe.started -or $probe.exit_code -ne 0) { throw ('Codex feature verification failed. {0}' -f $probe.error) }
    $output = @(([string]$probe.stdout -split '\r?\n') + ([string]$probe.stderr -split '\r?\n'))
    $line = @($output | Where-Object { [string]$_ -match '^respect_system_proxy\s+' } | Select-Object -First 1)
    if ($line.Count -eq 0) { throw 'Codex did not report respect_system_proxy after the write.' }
    $actual = $(if ([string]$line[0] -match '\s+true\s*$') { 'true' } else { 'false' })
    $expected = $(if ($ExpectedState -eq 'true') { 'true' } else { 'false' })
    if ($actual -ne $expected) { throw ("Codex reported {0}, expected {1}." -f $actual, $expected) }
}

function Test-CodexConnection {
    param(
        [Parameter(Mandatory = $true)][string]$CodexPath,
        [int]$HelpTimeoutMilliseconds = 5000,
        [int]$RequestTimeoutMilliseconds = 30000
    )

    $help = Invoke-NativeCommandWithTimeout -Path $CodexPath -Arguments @('exec', '--help') -TimeoutMilliseconds $HelpTimeoutMilliseconds
    if ($help.timed_out) {
        return [pscustomobject]@{
            supported = $false; attempted = $false; success = $false; timed_out = $true
            error_class = 'connection_help_timeout'; exit_code = $help.exit_code
            message = 'Codex exec capability detection timed out; no real request was sent.'
        }
    }
    if (-not $help.started -or $help.exit_code -ne 0) {
        return [pscustomobject]@{
            supported = $false; attempted = $false; success = $false; timed_out = $false
            error_class = 'connection_test_unsupported'; exit_code = $help.exit_code
            message = 'This Codex installation does not provide a reliable non-interactive connection test; no real request was sent.'
        }
    }
    $helpText = ([string]$help.stdout) + "`n" + ([string]$help.stderr)
    $requiredFlags = @('--ephemeral', '--skip-git-repo-check', '--json')
    $missingFlags = @($requiredFlags | Where-Object { $helpText -notmatch [regex]::Escape($_) })
    if ($missingFlags.Count -gt 0) {
        return [pscustomobject]@{
            supported = $false; attempted = $false; success = $false; timed_out = $false
            error_class = 'connection_test_unsupported'; exit_code = $help.exit_code
            message = 'This Codex version lacks the temporary non-interactive flags required for a safe connection test; no real request was sent.'
        }
    }

    $prompt = 'Reply only OK. Do not call tools, read files, or change anything.'
    $arguments = @('exec', '--ephemeral', '--skip-git-repo-check', '--json', $prompt)
    $request = Invoke-NativeCommandWithTimeout -Path $CodexPath -Arguments $arguments -TimeoutMilliseconds $RequestTimeoutMilliseconds
    if ($request.timed_out) {
        return [pscustomobject]@{
            supported = $true; attempted = $true; success = $false; timed_out = $true
            error_class = 'connection_request_timeout'; exit_code = $request.exit_code
            message = 'The real Codex request timed out and its process tree was stopped.'
        }
    }
    if (-not $request.started -or $request.exit_code -ne 0) {
        return [pscustomobject]@{
            supported = $true; attempted = $true; success = $false; timed_out = $false
            error_class = 'connection_request_failed'; exit_code = $request.exit_code
            message = 'The real Codex request failed. The configuration remains unchanged; check the account, proxy node, service status, or Desktop companion connection.'
        }
    }
    return [pscustomobject]@{
        supported = $true; attempted = $true; success = $true; timed_out = $false
        error_class = $null; exit_code = $request.exit_code
        message = 'A minimal real Codex request completed successfully.'
    }
}

function Invoke-CodexProxyRepair {
    param(
        [string]$CodexPath,
        [string]$ProxyEndpoint,
        [string]$ConfigPath,
        [object]$CodexInfoOverride,
        [object]$SystemProxyOverride
    )

    $plan = Get-RepairPlan -CodexPath $CodexPath -ProxyEndpoint $ProxyEndpoint -ConfigPath $ConfigPath -CodexInfoOverride $CodexInfoOverride -SystemProxyOverride $SystemProxyOverride
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
        [string]$ConfigPath,
        [object]$CodexInfoOverride,
        [object]$SystemProxyOverride
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
    $codex = $(if ($CodexInfoOverride) { $CodexInfoOverride } else { Get-RecommendedCodexInfo -CodexPath $CodexPath })
    if (-not $codex -or -not $codex.supports_system_proxy) { throw 'A verified Codex engine is required before restoring a snapshot.' }
    $proxyInfo = $(if ($SystemProxyOverride) { $SystemProxyOverride } else { Get-WindowsSystemProxy })
    $restoreSnapshot = New-ConfigSnapshot -ConfigPath $path -Operation 'restore' -BeforeExists $currentExists -BeforeText $currentText -AfterExists $targetExists -AfterText $targetText -CodexInfo $codex -ProxyInfo $proxyInfo -TargetSnapshotId $SnapshotId
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

if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function @(
        'Get-CodexConfigPath',
        'Get-FeatureStateFromText',
        'Enable-SystemProxyFeatureText',
        'Get-CodexConfigStatus',
        'Invoke-NativeCommandWithTimeout',
        'Get-CodexInstallations',
        'Get-CodexEngineInfo',
        'Get-WindowsSystemProxy',
        'Test-ProxyRoute',
        'Test-ProxyInput',
        'Get-ConfigSnapshots',
        'Resolve-CodexTargets',
        'Get-DetectionReport',
        'Get-RepairPlan',
        'Test-CodexConnection',
        'Invoke-CodexProxyRepair',
        'Restore-CodexProxySnapshot'
    )
}

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
