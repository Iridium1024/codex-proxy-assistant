param(
    [ValidateSet('menu', 'detect', 'plan', 'apply', 'temporary', 'test-connection', 'list-snapshots', 'restore')]
    [string]$Action = 'menu',
    [string]$CodexPath,
    [string]$ProxyEndpoint,
    [string]$ConfigPath,
    [string]$SnapshotId,
    [switch]$Yes,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding

$modulePath = Join-Path $PSScriptRoot 'powershell\CodexProxy.Core.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'powershell\CodexProxy.Core.psm1'
}
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "缺少核心模块：CodexProxy.Core.psm1"
}
Import-Module $modulePath -Force

$script:State = [ordered]@{
    CodexPath = $CodexPath
    ProxyEndpoint = $ProxyEndpoint
    ConfigPath = $ConfigPath
    Report = $null
}

$script:MessageMap = @{
    'The existing config has an unsafe or duplicate [features] value.' = '现有配置中的 [features] 段重复或含有无法安全处理的值。'
    'No runnable Codex engine was found.' = '未找到可运行的 Codex Desktop 或 CLI。'
    'The selected Codex engine did not confirm respect_system_proxy support.' = '所选 Codex 未确认支持系统代理功能；请先更新 Codex。'
    'Windows system proxy, PAC, or WPAD is not enabled.' = '未启用 Windows 系统代理、PAC 或自动发现。'
    'The configured Windows proxy port is not reachable.' = 'Windows 当前代理端口不可达；请确认代理软件正在运行。'
    'The configured Windows proxy is not an HTTP or HTTPS proxy supported by persistent repair.' = 'Windows 当前代理不是持久修复支持的 HTTP/HTTPS（或 Mixed）端口。'
    'The configured Windows proxy did not pass the HTTPS route test.' = 'Windows 当前代理未通过 HTTPS 链路验证。'
    'The proxy entered in the UI is invalid or unreachable.' = '手工输入的代理地址无效或不可达。'
    'The proxy entered in the UI is not an HTTP or HTTPS proxy supported by persistent repair.' = '手工输入的代理不是持久修复支持的 HTTP/HTTPS（或 Mixed）端口。'
    'The proxy entered in the UI did not pass the HTTPS route test.' = '手工输入的代理未通过 HTTPS 链路验证。'
    'The entered proxy differs from the Windows system proxy; persistent repair would not use it.' = '手工输入的代理与 Windows 系统代理不同；持久修复不会使用该地址。'
    'Proxy URLs containing a user name or password are not accepted.' = '不支持在代理 URL 中写入用户名或密码。'
    'PAC or WPAD is detected; static HTTPS endpoint validation is not available and Codex will resolve it at runtime.' = '已检测到 PAC/WPAD；程序无法静态验证其 HTTPS 路径，将由 Codex 在运行时解析。'
    'The persistent setting is already enabled; applying would make no change.' = '持久系统代理设置已经启用，无需再次修改。'
}

function Convert-ConsoleMessage {
    param([object]$Message)
    $text = [string]$Message
    if ($script:MessageMap.ContainsKey($text)) { return [string]$script:MessageMap[$text] }
    return $text
}

function Write-Title {
    Write-Host ''
    Write-Host 'Codex Proxy Assistant · 控制台版 0.1.3' -ForegroundColor White
    Write-Host '自动识别 Codex 与 Windows 系统代理，帮助缓解 VPN 环境下的频繁重连。' -ForegroundColor DarkGray
}

function Write-Section {
    param([string]$Text)
    Write-Host ''
    Write-Host ("── {0} ──" -f $Text) -ForegroundColor Cyan
}

function Write-StateLine {
    param(
        [ValidateSet('ok', 'warn', 'error', 'info')][string]$Level,
        [string]$Text
    )
    $prefix = switch ($Level) {
        'ok' { '[正常]' }
        'warn' { '[注意]' }
        'error' { '[失败]' }
        default { '[信息]' }
    }
    $color = switch ($Level) {
        'ok' { 'Green' }
        'warn' { 'Yellow' }
        'error' { 'Red' }
        default { 'Gray' }
    }
    Write-Host ("{0} {1}" -f $prefix, $Text) -ForegroundColor $color
}

function Wait-ForUser {
    Write-Host ''
    [void](Read-Host '按 Enter 返回主菜单')
}

function Get-FeatureStateLabel {
    param([string]$State)
    switch ($State) {
        'true' { '已启用' }
        'false' { '尚未启用' }
        'missing' { '尚未配置' }
        'invalid-duplicate-section' { '存在重复 [features] 段' }
        'invalid-duplicate-key' { '存在重复设置' }
        'invalid-value' { '设置值无法识别' }
        default { $State }
    }
}

function Get-TargetKindLabel {
    param([string]$Kind)
    if ($Kind -eq 'desktop') { return 'Codex Desktop' }
    return 'Codex CLI'
}

function Invoke-ConsoleDetection {
    param([switch]$Silent)
    if (-not $Silent) { Write-StateLine info '正在检测 Codex、系统代理和配置，请稍候……' }
    $script:State.Report = Get-DetectionReport -CodexPath $script:State.CodexPath -ConfigPath $script:State.ConfigPath
    return $script:State.Report
}

function Get-CurrentReport {
    if (-not $script:State.Report) { return Invoke-ConsoleDetection -Silent }
    return $script:State.Report
}

function Get-EffectiveCodexPath {
    $report = Get-CurrentReport
    if (-not [string]::IsNullOrWhiteSpace($script:State.CodexPath)) { return $script:State.CodexPath }
    return [string]$report.recommended_path
}

function Get-EffectiveProxyEndpoint {
    $report = Get-CurrentReport
    if (-not [string]::IsNullOrWhiteSpace($script:State.ProxyEndpoint)) { return $script:State.ProxyEndpoint }
    if ($report.proxy.source -eq 'manual') { return [string]$report.proxy.display_endpoint }
    return $null
}

function Show-DetectionReport {
    param([object]$Report)

    Write-Section 'Codex'
    if ($Report.recommended) {
        $target = $Report.recommended
        $kind = Get-TargetKindLabel -Kind ([string]$target.kind)
        $version = $(if ([string]::IsNullOrWhiteSpace([string]$target.version)) { '版本未知' } else { [string]$target.version })
        if ($target.runnable -and $target.supports_system_proxy) {
            Write-StateLine ok ("已选择 {0} · {1} · 支持系统代理" -f $kind, $version)
        } elseif ($target.runnable) {
            Write-StateLine warn ("已找到 {0} · {1}，但未确认支持系统代理；建议更新 Codex。" -f $kind, $version)
        } else {
            Write-StateLine error ("{0} 无法运行或无法验证。" -f $kind)
        }
        Write-StateLine info ("路径：{0}" -f $target.path)
    } else {
        Write-StateLine error '未找到可运行的 Codex。可在“高级设置”中手工选择路径。'
    }
    if (@($Report.skipped).Count -gt 0) {
        Write-StateLine warn ("另有 {0} 个候选路径因不可运行或超时而跳过。" -f @($Report.skipped).Count)
    }

    Write-Section 'Windows 系统代理'
    $proxy = $Report.proxy
    if (-not $proxy.configured) {
        Write-StateLine warn '未检测到系统代理、PAC 或自动发现。请先在代理软件中启用“系统代理”。'
    } elseif ($proxy.source -eq 'manual') {
        Write-StateLine info ("地址：{0}" -f $proxy.display_endpoint)
        if ($proxy.https_reachable -eq $true) {
            $suffix = $(if ($proxy.used_ssl_no_revoke) { '（使用兼容的证书吊销回退）' } else { '' })
            Write-StateLine ok ("代理端口已开放，且 HTTPS 链路可用{0}。" -f $suffix)
        } elseif ($proxy.tcp_reachable -eq $false) {
            Write-StateLine error '代理端口不可达。请启动代理软件并核对 HTTP/Mixed 端口。'
        } elseif ($null -eq $proxy.https_reachable) {
            Write-StateLine warn '代理端口已开放，但系统缺少 curl.exe，未完成 HTTPS 验证。'
        } else {
            Write-StateLine error '代理端口已开放，但 HTTPS 链路测试失败；请核对端口或切换节点。'
        }
    } elseif ($proxy.source -eq 'pac') {
        Write-StateLine warn '已检测到 PAC；静态 HTTPS 验证不适用，将由 Codex 在运行时解析。'
    } else {
        Write-StateLine warn '已检测到 WPAD 自动发现；静态 HTTPS 验证不适用，将由 Codex 在运行时解析。'
    }

    Write-Section 'Codex 配置'
    $configState = [string]$Report.config.feature_state
    $configLevel = $(if ($configState -eq 'true') { 'ok' } elseif ($configState -like 'invalid-*') { 'error' } else { 'warn' })
    Write-StateLine $configLevel ("系统代理设置：{0}" -f (Get-FeatureStateLabel -State $configState))
    Write-StateLine info ("配置文件：{0}" -f $Report.config.path)

    Write-Section '建议的下一步'
    if (-not $Report.recommended) {
        Write-StateLine warn '安装或更新 Codex，或在高级设置中手工选择 Codex 路径。'
    } elseif (-not $Report.recommended.supports_system_proxy) {
        Write-StateLine warn '先更新所选 Codex，再重新检测。'
    } elseif (-not $proxy.configured) {
        Write-StateLine warn '先在 VPN/代理软件中启用 Windows 系统代理，再重新检测。'
    } elseif ($proxy.source -eq 'manual' -and $proxy.https_reachable -ne $true) {
        Write-StateLine warn '先让代理 HTTPS 测试通过，再预览持久修复。'
    } elseif ($configState -eq 'true') {
        Write-StateLine ok '配置已启用。请完全退出并重新打开 Codex；仍有疑问时可运行“验证实际连接”。'
    } elseif ($configState -like 'invalid-*') {
        Write-StateLine error '配置存在程序无法安全处理的内容；请先人工检查 config.toml。'
    } else {
        Write-StateLine ok '环境符合条件。请选择“预览持久修复”，确认后再应用。'
    }
}

function Show-RepairPlan {
    param([object]$Plan)
    Write-Section '修改预览'
    Write-StateLine info ("目标：{0}" -f $(if ($Plan.codex) { "$(Get-TargetKindLabel $Plan.codex.kind) · $($Plan.codex.version)" } else { '未找到' }))
    Write-StateLine info ("配置：{0}" -f $Plan.config.path)
    Write-StateLine info ("respect_system_proxy：{0} → true" -f $Plan.before_state)
    foreach ($warning in @($Plan.warnings)) { Write-StateLine warn (Convert-ConsoleMessage $warning) }
    foreach ($errorItem in @($Plan.errors)) { Write-StateLine error (Convert-ConsoleMessage $errorItem) }
    if ($Plan.can_apply) {
        if ($Plan.needs_change) { Write-StateLine ok '执行条件已通过；应用时会先创建快照，再写入并验证。' }
        else { Write-StateLine ok '当前已启用，无需写入。' }
    } else {
        Write-StateLine error '当前条件未通过，程序不会修改配置。'
    }
}

function Invoke-MenuDetect {
    try {
        $report = Invoke-ConsoleDetection
        Show-DetectionReport -Report $report
    } catch {
        Write-StateLine error $_.Exception.Message
    }
}

function Invoke-MenuPlan {
    try {
        Write-StateLine info '正在生成修改预览……'
        $plan = Get-RepairPlan -CodexPath (Get-EffectiveCodexPath) -ProxyEndpoint $script:State.ProxyEndpoint -ConfigPath $script:State.ConfigPath
        Show-RepairPlan -Plan $plan
    } catch {
        Write-StateLine error $_.Exception.Message
    }
}

function Invoke-MenuApply {
    try {
        Write-StateLine info '正在重新检查执行条件……'
        $plan = Get-RepairPlan -CodexPath (Get-EffectiveCodexPath) -ProxyEndpoint $script:State.ProxyEndpoint -ConfigPath $script:State.ConfigPath
        Show-RepairPlan -Plan $plan
        if (-not $plan.can_apply) { return }
        if (-not $plan.needs_change) { return }
        Write-Host ''
        Write-Host '程序只会修改 Codex 用户配置；不会修改 Windows 代理、VPN 或 Codex 安装文件。' -ForegroundColor Yellow
        $confirmation = Read-Host '确认应用上述修改？输入 Y 后按 Enter'
        if ($confirmation -notmatch '^(?i)y(es)?$') {
            Write-StateLine info '已取消，未修改任何内容。'
            return
        }
        Write-StateLine info '正在创建快照、写入配置并让 Codex 验证……'
        $result = Invoke-CodexProxyRepair -CodexPath (Get-EffectiveCodexPath) -ProxyEndpoint $script:State.ProxyEndpoint -ConfigPath $script:State.ConfigPath
        if ($result.changed) {
            Write-StateLine ok '持久修复已应用并通过 Codex 验证。'
            Write-StateLine info ("快照：{0}" -f $result.snapshot_id)
        } else {
            Write-StateLine ok '配置已经启用，本次未写入。'
        }
        Write-StateLine warn '请完全退出并重新打开 Codex，再观察重连情况。'
        [void](Invoke-ConsoleDetection -Silent)
    } catch {
        Write-StateLine error (Convert-ConsoleMessage $_.Exception.Message)
    }
}

function Get-TemporaryCliPath {
    $report = Get-CurrentReport
    $effective = Get-EffectiveCodexPath
    $selected = @($report.engines | Where-Object { $_.path -eq $effective } | Select-Object -First 1)
    if ($selected.Count -gt 0 -and $selected[0].kind -eq 'cli' -and $selected[0].runnable) { return [string]$selected[0].path }
    $cli = @($report.engines | Where-Object { $_.kind -eq 'cli' -and $_.runnable } | Sort-Object @{ Expression = { -not $_.supports_system_proxy } }, source | Select-Object -First 1)
    if ($cli.Count -gt 0) { return [string]$cli[0].path }
    return $null
}

function Invoke-MenuTemporary {
    try {
        $cliPath = Get-TemporaryCliPath
        if ([string]::IsNullOrWhiteSpace($cliPath)) {
            Write-StateLine warn '未找到可运行的 Codex CLI。临时试运行不适用于 Desktop 宿主程序。'
            return
        }
        $endpoint = Get-EffectiveProxyEndpoint
        if ([string]::IsNullOrWhiteSpace($endpoint)) {
            Write-StateLine warn '没有可用的手工代理地址。请先启用 Windows 手工代理，或在高级设置中输入地址。'
            return
        }
        Write-StateLine info '正在验证代理并准备新的临时 CLI 窗口……'
        $result = Start-CodexWithProxy -CodexPath $cliPath -ProxyEndpoint $endpoint
        Write-StateLine ok ("已启动临时 Codex CLI（PID {0}）。" -f $result.process_id)
        Write-StateLine info '代理变量只存在于新窗口及其子进程中，关闭窗口后失效。'
    } catch {
        Write-StateLine error (Convert-ConsoleMessage $_.Exception.Message)
    }
}

function Invoke-MenuConnectionTest {
    try {
        $path = Get-EffectiveCodexPath
        if ([string]::IsNullOrWhiteSpace($path)) {
            Write-StateLine warn '未找到可用于验证的 Codex。'
            return
        }
        Write-Host '此操作会使用当前 Codex 登录状态发送一个最小、无工具的临时请求，可能消耗少量额度。' -ForegroundColor Yellow
        $confirmation = Read-Host '确认继续？输入 TEST 后按 Enter'
        if ($confirmation -cne 'TEST') {
            Write-StateLine info '已取消，没有发送请求。'
            return
        }
        Write-StateLine info '正在发送最小连接验证请求（最长约 30 秒）……'
        $result = Test-CodexConnection -CodexPath $path
        if ($result.success) {
            Write-StateLine ok 'Codex 最小真实请求已成功完成。'
        } elseif (-not $result.attempted) {
            Write-StateLine warn '当前 Codex 缺少安全的非交互验证参数，因此没有发送请求。'
        } elseif ($result.timed_out) {
            Write-StateLine error '连接验证超时，相关进程树已终止；配置没有被更改。'
        } else {
            Write-StateLine error '真实请求失败。请检查登录状态、代理节点、服务状态或 Desktop 附属连接。'
        }
    } catch {
        Write-StateLine error $_.Exception.Message
    }
}

function Invoke-MenuRestore {
    try {
        $snapshots = @(Get-ConfigSnapshots -ConfigPath $script:State.ConfigPath | Where-Object { $_.operation -eq 'apply' -and $_.result -eq 'success' })
        if ($snapshots.Count -eq 0) {
            Write-StateLine warn '没有可恢复的成功应用快照。'
            return
        }
        Write-Section '可恢复快照'
        for ($index = 0; $index -lt $snapshots.Count; $index++) {
            $item = $snapshots[$index]
            $time = ([string]$item.created_at_local).Replace('T', ' ')
            if ($time.Length -gt 19) { $time = $time.Substring(0, 19) }
            Write-Host ("{0,2}. {1} · {2} → {3}" -f ($index + 1), $time, $item.before_state, $item.after_state)
        }
        Write-Host ' 0. 取消'
        $choiceText = Read-Host '请选择快照编号'
        $choice = 0
        if (-not [int]::TryParse($choiceText, [ref]$choice) -or $choice -lt 1 -or $choice -gt $snapshots.Count) {
            Write-StateLine info '已取消恢复。'
            return
        }
        $target = $snapshots[$choice - 1]
        Write-Host ("将恢复快照 {0}。恢复前还会为当前配置创建安全快照。" -f $target.id) -ForegroundColor Yellow
        $confirmation = Read-Host '确认恢复？输入 Y 后按 Enter'
        if ($confirmation -notmatch '^(?i)y(es)?$') {
            Write-StateLine info '已取消恢复。'
            return
        }
        $result = Restore-CodexProxySnapshot -SnapshotId $target.id -CodexPath (Get-EffectiveCodexPath) -ConfigPath $script:State.ConfigPath
        Write-StateLine ok '快照已恢复并通过 Codex 验证。'
        Write-StateLine info ("恢复前安全快照：{0}" -f $result.safety_snapshot_id)
        [void](Invoke-ConsoleDetection -Silent)
    } catch {
        Write-StateLine error (Convert-ConsoleMessage $_.Exception.Message)
    }
}

function Invoke-AdvancedSettings {
    while ($true) {
        Clear-Host
        Write-Title
        Write-Section '高级设置'
        Write-Host ("1. 手工选择 Codex 路径  当前：{0}" -f $(if ($script:State.CodexPath) { $script:State.CodexPath } else { '自动' }))
        Write-Host ("2. 手工输入代理地址       当前：{0}" -f $(if ($script:State.ProxyEndpoint) { $script:State.ProxyEndpoint } else { '自动读取系统代理' }))
        Write-Host '3. 清除手工设置并恢复自动检测'
        Write-Host '4. 查看当前完整检测结果'
        Write-Host '0. 返回主菜单'
        Write-Host ''
        $choice = (Read-Host '请选择').Trim()
        switch ($choice) {
            '1' {
                $value = Read-Host '输入 Codex 的 .exe/.cmd/.bat 完整路径（留空表示取消）'
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $info = Get-CodexEngineInfo -Path $value.Trim('"')
                    if ($info.runnable) {
                        $script:State.CodexPath = $info.path
                        $script:State.Report = $null
                        Write-StateLine ok ("已选择：{0}" -f $info.path)
                    } else {
                        Write-StateLine error ("该路径无法验证：{0}" -f $info.error)
                    }
                    Wait-ForUser
                }
            }
            '2' {
                $value = Read-Host '输入代理地址，例如 http://127.0.0.1:XXXX（请将 XXXX 替换为实际端口；留空表示取消）'
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $info = Test-ProxyInput -Endpoint $value
                    if ($info.valid -and $info.https_reachable -eq $true) {
                        $script:State.ProxyEndpoint = $info.normalized
                        Write-StateLine ok ("代理 HTTPS 验证通过：{0}" -f $info.display_endpoint)
                    } elseif ($info.tcp_reachable -eq $true) {
                        Write-StateLine error '端口已开放，但 HTTPS 验证失败；未保存该地址。'
                    } else {
                        Write-StateLine error '代理地址无效或端口不可达；未保存该地址。'
                    }
                    Wait-ForUser
                }
            }
            '3' {
                $script:State.CodexPath = $null
                $script:State.ProxyEndpoint = $null
                $script:State.Report = $null
                Write-StateLine ok '已清除手工设置。'
                Wait-ForUser
            }
            '4' {
                try { Show-DetectionReport -Report (Invoke-ConsoleDetection) } catch { Write-StateLine error $_.Exception.Message }
                Wait-ForUser
            }
            '0' { return }
        }
    }
}

function Start-InteractiveMenu {
    try { [void](Invoke-ConsoleDetection -Silent) } catch { }
    while ($true) {
        Clear-Host
        Write-Title
        if ($script:State.Report) {
            $targetText = $(if ($script:State.Report.recommended) { "$(Get-TargetKindLabel $script:State.Report.recommended.kind) · $($script:State.Report.recommended.version)" } else { '未找到' })
            $proxyText = $(if ($script:State.Report.proxy.configured) { [string]$script:State.Report.proxy.display_endpoint } else { '未检测到' })
            if ([string]::IsNullOrWhiteSpace($proxyText)) { $proxyText = $script:State.Report.proxy.source.ToUpperInvariant() }
            $configText = Get-FeatureStateLabel ([string]$script:State.Report.config.feature_state)
            Write-Section '当前摘要'
            Write-Host ("Codex：{0}" -f $targetText)
            Write-Host ("代理： {0}" -f $proxyText)
            Write-Host ("配置： {0}" -f $configText)
        } else {
            Write-StateLine warn '尚未完成检测。'
        }
        Write-Section '操作菜单'
        Write-Host '1. 自动检测并查看建议'
        Write-Host '2. 预览持久修复'
        Write-Host '3. 应用持久修复'
        Write-Host '4. 临时 CLI 试运行（不写配置）'
        Write-Host '5. 验证实际连接（可能消耗少量额度）'
        Write-Host '6. 恢复配置快照'
        Write-Host '7. 高级设置（手工路径/代理）'
        Write-Host '0. 退出'
        Write-Host ''
        $choice = (Read-Host '请选择').Trim()
        Clear-Host
        Write-Title
        switch ($choice) {
            '1' { Invoke-MenuDetect; Wait-ForUser }
            '2' { Invoke-MenuPlan; Wait-ForUser }
            '3' { Invoke-MenuApply; Wait-ForUser }
            '4' { Invoke-MenuTemporary; Wait-ForUser }
            '5' { Invoke-MenuConnectionTest; Wait-ForUser }
            '6' { Invoke-MenuRestore; Wait-ForUser }
            '7' { Invoke-AdvancedSettings }
            '0' { return 0 }
            default { Write-StateLine warn '请输入 0 到 7。'; Start-Sleep -Milliseconds 700 }
        }
    }
}

function Resolve-DirectCodexPath {
    if (-not [string]::IsNullOrWhiteSpace($CodexPath)) { return $CodexPath }
    $report = Get-DetectionReport -ConfigPath $ConfigPath
    if (-not $report.recommended_path) { throw '未找到可运行的 Codex。' }
    return [string]$report.recommended_path
}

function Resolve-DirectCliPath {
    if (-not [string]::IsNullOrWhiteSpace($CodexPath)) {
        $info = Get-CodexEngineInfo -Path $CodexPath
        if (-not $info.runnable -or $info.kind -ne 'cli') { throw '临时试运行需要可运行的 Codex CLI 路径。' }
        return [string]$info.path
    }
    $report = Get-DetectionReport -ConfigPath $ConfigPath
    $candidate = @($report.engines | Where-Object { $_.kind -eq 'cli' -and $_.runnable } | Select-Object -First 1)
    if ($candidate.Count -eq 0) { throw '未找到可运行的 Codex CLI。' }
    return [string]$candidate[0].path
}

function Invoke-DirectAction {
    switch ($Action) {
        'detect' { return Get-DetectionReport -CodexPath $CodexPath -ConfigPath $ConfigPath }
        'plan' { return Get-RepairPlan -CodexPath (Resolve-DirectCodexPath) -ProxyEndpoint $ProxyEndpoint -ConfigPath $ConfigPath }
        'apply' {
            if (-not $Yes) { throw '非交互应用必须显式添加 -Yes。' }
            return Invoke-CodexProxyRepair -CodexPath (Resolve-DirectCodexPath) -ProxyEndpoint $ProxyEndpoint -ConfigPath $ConfigPath
        }
        'temporary' {
            if ([string]::IsNullOrWhiteSpace($ProxyEndpoint)) { throw '临时试运行必须提供 -ProxyEndpoint。' }
            return Start-CodexWithProxy -CodexPath (Resolve-DirectCliPath) -ProxyEndpoint $ProxyEndpoint
        }
        'test-connection' {
            if (-not $Yes) { throw '真实连接验证可能消耗少量额度；非交互执行必须显式添加 -Yes。' }
            return Test-CodexConnection -CodexPath (Resolve-DirectCodexPath)
        }
        'list-snapshots' { return @(Get-ConfigSnapshots -ConfigPath $ConfigPath) }
        'restore' {
            if ([string]::IsNullOrWhiteSpace($SnapshotId)) { throw '恢复必须提供 -SnapshotId。' }
            if (-not $Yes) { throw '非交互恢复必须显式添加 -Yes。' }
            return Restore-CodexProxySnapshot -SnapshotId $SnapshotId -CodexPath (Resolve-DirectCodexPath) -ConfigPath $ConfigPath
        }
    }
}

if ($Action -eq 'menu') {
    if ($Json) { throw 'menu 模式不支持 -Json。' }
    exit (Start-InteractiveMenu)
}

$exitCode = 0
$data = $null
$errorText = $null
try {
    $data = Invoke-DirectAction
} catch {
    $exitCode = 1
    $errorText = $_.Exception.Message
}

if ($Json) {
    [ordered]@{
        ok = ($exitCode -eq 0)
        action = $Action
        data = $data
        error = $errorText
        exit_code = $exitCode
    } | ConvertTo-Json -Depth 16 -Compress
} elseif ($exitCode -ne 0) {
    Write-StateLine error $errorText
} else {
    switch ($Action) {
        'detect' { Show-DetectionReport -Report $data }
        'plan' { Show-RepairPlan -Plan $data }
        default { $data | Format-List | Out-Host }
    }
}
exit $exitCode
