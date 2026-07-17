# Codex CLI 与桌面 App 在 VPN/系统代理下的重连阻塞现象

日期：2026-07-13

状态：现象归档，供后续独立项目立项与复现。本文不是根因结论，也不是 Beacon 发布文档。

## 一、摘要

Windows 11 使用 Clash Verge 系统代理时，Codex CLI 非交互请求和 Codex Desktop 均出现过网络冷启动或重连异常：

- Codex CLI `exec resume --json` 两次连续经历 WebSocket 重连 2/5 至 5/5，随后回退 HTTPS 仍超时，单次约 120 秒。
- Codex Desktop 的启动日志在相近时段记录了推荐 skills 的 GitHub fetch 超时/连接重置，以及登录后 Statsig bootstrap 超时。
- 用户观察到 Desktop 重启后的第一个任务更容易显示“重新连接”，后续任务通常更稳定。该规律尚未经过统计实验。
- 在 `~/.codex/config.toml` 启用实验性 `features.respect_system_proxy = true` 后，一次相同 Codex CLI 激活在约 11 秒内完成；但 Desktop 的附属 GitHub fetch 仍出现过连接重置。
- 同一台机器上，普通 `git fetch` 曾直接连接重置，而仅对该命令显式指定 `http://127.0.0.1:7897` 后立即成功。这支持“不同子进程对 Windows 系统代理的继承不一致”，但不能单独证明 Codex 的最终根因。

当前最合理的工作假设是：系统代理已启用，但 Codex Desktop、其内置 `codex.exe`、npm 安装的 Codex CLI、Git、HTTP/WebSocket 客户端等不同进程并不稳定地采用同一代理路径；首次启动还叠加认证、配置、实验开关、连接池与附属服务初始化。Beacon 会为每次 registered-session activation 启动新的 `codex exec resume` 进程，因此容易重复触发该冷启动路径，但现有代码没有接管 Codex 的网络连接，也不是网络超时的充分原因。

## 二、测试环境

| 项目 | 观察值 |
| --- | --- |
| 操作系统 | Windows 11 专业版，10.0.26200，build 26200 |
| 系统代理 | WinINET `ProxyEnable=1` |
| 代理地址 | `127.0.0.1:7897` |
| 本地监听 | 归档时 `127.0.0.1:7897` 处于 LISTENING |
| 代理软件 | Clash Verge，系统代理模式，用户提供 |
| npm Codex CLI | `codex-cli 0.144.1` |
| Beacon 使用的 CLI | `%APPDATA%\npm\codex.cmd` |
| Desktop 内置客户端 | WindowsApps 包内 `app\resources\codex.exe`，日志中观察到多个 26.707.x 包版本 |
| 用户级 Codex 配置 | `%USERPROFILE%\.codex\config.toml` |
| 实验配置 | `[features] respect_system_proxy = true` |

当前官方 [Codex Configuration Reference](https://developers.openai.com/codex/config-reference) 确认用户级配置位于 `~/.codex/config.toml`，但截至归档时没有列出 `respect_system_proxy`。本机 Codex 运行输出将该项明确标记为 under-development feature。因此它只能作为实验变量，不能视为稳定、受支持的长期修复接口。官方 [Desktop app Settings](https://developers.openai.com/codex/app/settings) 也未提供对应的可见代理设置说明。

## 三、需要区分的运行形态

### 1. Codex Desktop

Desktop 是 Windows App/Electron 宿主。日志显示它会通过 stdio 启动包内的 `app\resources\codex.exe`，同时还运行推荐 skills 获取、Statsig bootstrap、浏览器运行时等附属网络路径。

因此，Desktop 中的“重新连接”不一定只来自一次模型请求；应用启动、功能配置、skills Git fetch 或其它服务初始化均可能失败，而且这些组件未必共享完全相同的代理实现。

### 2. 交互式 Codex CLI

用户直接在终端启动的 `codex` 使用 npm 安装的 CLI。它与 Desktop 内置 executable 不是同一个文件路径，版本更新节奏也可能不同。

### 3. 非交互 `codex exec` / `exec resume`

Beacon 使用 `codex.cmd exec resume --json --output-last-message ...`。每次 activation 都是新的本地 CLI 进程，不复用 Desktop 已经建立的模型连接或进程内连接池。它会读取已注册 session id 并请求 provider 恢复该会话，但这不等于控制 Desktop 当前窗口。

## 四、时间线证据

以下时间为 Asia/Shanghai。

### 2026-07-13 09:27 至 09:32，Desktop 启动期网络异常

- 09:27:48，Desktop 日志记录启动包内 `codex.exe`。
- 09:28:19，推荐 skills 的 Git fetch 在 30 秒后超时。
- 09:31:56，另一轮推荐 skills fetch 无法连接 `github.com:443`，约 21 秒后失败。

这些事件不经过 Beacon，证明当时本机 Desktop 自身的附属网络路径已有异常。

### 2026-07-13 09:57 至 09:59，Codex CLI 第一次 120 秒超时

Beacon activation 已成功创建 provider 进程。CLI stdout 依次记录：

```text
thread.started
turn.started
Reconnecting... 2/5 (request timed out)
Reconnecting... 3/5 (request timed out)
Reconnecting... 4/5 (request timed out)
Reconnecting... 5/5 (request timed out)
Falling back from WebSockets to HTTPS transport. request timed out
```

没有 `agent_message`，约 121 秒后 provider lifecycle 以 timeout 结束。

### 2026-07-13 10:16 至 10:18，Codex CLI 第二次同型超时

另一次无副作用 PowerShell probe 使用相同 activation 路径，stdout 序列与第一次一致，仍无 `agent_message`，约 121 秒后超时。

这两次失败发生在模型生成任何可见回答之前，因此不能归因于 PowerShell probe 本身。probe 没有获得执行机会。

### 2026-07-13 11:06，Desktop 重启后的启动异常

- 11:06:49，新的 Desktop 进程启动包内 `codex.exe`。
- 11:06:59，Desktop 记录 `Timed out while fetching post-login Statsig bootstrap`。
- 用户在 UI 中观察到重启后第一个任务更容易出现重连，后续任务较稳定。

日志支持“重启后的启动期存在网络超时”，但目前没有足够样本证明“每次第一个任务必然失败”。

### 2026-07-13 12:24，启用实验配置后的成功样本

相同 Beacon/Codex CLI activation 在 11.1 秒内完成。stdout 包含：

```text
Under-development features enabled: respect_system_proxy
turn.started
item.completed: agent_message "Pong."
turn.completed
```

该样本证明配置已被此 CLI 进程读取，且本次模型传输成功；它只形成一次正相关 A/B 证据，不足以排除同时发生的网络恢复、节点切换、连接预热或版本变化。

### 2026-07-13 12:25 至 12:26，Desktop 附属网络仍可失败

新的 Desktop 进程启动后，推荐 skills Git fetch 仍因 `Recv failure: Connection was reset` 失败。这说明即使模型请求成功，不能推断 Desktop 内所有网络子系统都已正确使用代理。

### 归档期间的独立 Git 探针

- 未显式指定代理的 `git fetch origin main` 返回 `Recv failure: Connection was reset`。
- 同一命令增加一次性 `http.proxy=http://127.0.0.1:7897` 后成功。

这不是 Codex 模型链路测试，但它直接证明“Windows 系统代理已开启”不等于“所有命令行网络客户端会自动使用该代理”。

## 五、与相邻问题的边界

### 1. Beacon 旧版把错误文本当作回复

此前 Beacon 会把 Codex JSON stdout 中任意 `message/text/content` 当作最终回答，因此可能把 `Reconnecting...` 和 HTTPS fallback 错误写成目标 agent 的 response。macro-step 30.8 已修复此问题：只有 `item.completed/agent_message` 或受控 legacy result 才能成为回复。

这项修复保证状态不再误报，但不会改善 Codex 网络连接。

### 2. `CreateProcessAsUserW failed: 5`

早期 Codex 被动回复测试中还出现过 PowerShell 子进程创建被拒绝，稍后又自行恢复。现有证据只说明它与 provider timeout 曾在同一时间窗口出现，没有证据表明 VPN 导致 Windows sandbox/command runner 的访问拒绝。

后续项目应将它作为独立的 Windows sandbox/进程令牌问题，不应与 WebSocket/HTTPS 重连合并为一个根因。

### 3. Beacon 每次启动新进程

Beacon 的确会让每次 registered-session activation 进入一个新的 `codex exec resume` 进程，因此可能放大首次连接成本。当前没有证据表明 Beacon 修改了系统代理、Codex 配置、DNS、TLS、WebSocket 或 provider endpoint。

## 六、当前判断

### 已确认

- 系统代理和本地代理监听在测试时存在。
- CLI 的失败发生在 WebSocket 多次重连和 HTTPS fallback 均超时之后。
- Desktop 独立于 Beacon 记录了 GitHub fetch、Statsig bootstrap 等网络超时。
- 不同形态使用不同 executable 路径和进程生命周期。
- `respect_system_proxy=true` 被 CLI 读取，并与一次快速成功样本同时出现。
- 显式代理可使一次原本 connection reset 的 Git fetch 成功。
- Beacon 30.8 已消除“把重连错误当回复”的二次故障。

### 高概率但未完全证明

- 不同进程对 WinINET 系统代理、环境变量代理和应用内代理的继承不一致。
- WebSocket 经当前代理节点/转发模式不稳定，fallback HTTPS 也没有稳定走通相同代理路径。
- Desktop 首任务还叠加冷启动、认证和功能 bootstrap，后续任务因连接/缓存预热而更稳定。
- Beacon 的新进程激活模式会反复触发 CLI 冷连接，但不是原始网络故障来源。

### 尚未确认

- Desktop 内置 `codex.exe` 与 npm CLI 是否对 `respect_system_proxy` 使用完全相同的代码路径。
- Desktop UI 的每条“重新连接”提示对应哪个 endpoint、协议和子进程。
- Clash Verge 当前节点、规则、DNS、TUN/系统代理模式中的哪一层导致 reset/timeout。
- 是否存在账号、服务端区域、WebSocket 中间设备或 IPv4/IPv6 路由因素。
- `CreateProcessAsUserW failed: 5` 是否与网络问题存在任何因果关系。

## 七、建议创建的独立项目

建议项目暂名：`codex-windows-proxy-diagnostics`。

### 测试矩阵

每种组合至少重复 10 次，分别记录冷启动首任务与同进程后续任务：

| Surface | 操作 |
| --- | --- |
| Desktop | 完全退出后首任务、第二任务、已有任务继续 |
| CLI interactive | 新进程首轮、同进程第二轮 |
| CLI exec | `codex exec --json` |
| CLI exec resume | `codex exec resume --json <session-id> -` |
| Beacon | `--wait once`，仅作为上层对照组 |

代理变量至少覆盖：

- Clash 系统代理开/关。
- Clash TUN 与系统代理模式分别测试。
- `respect_system_proxy` 开/关。
- 显式 `HTTP_PROXY`、`HTTPS_PROXY`、`ALL_PROXY` 与无环境变量。
- 直连、不同代理节点和稳定的对照网络。

### 每轮采集

- 精确开始/结束时间、是否首任务、surface、executable 路径与版本。
- `--json` 原始 lifecycle/error 事件，不保存私有 prompt/answer 正文。
- Desktop 日志中的网络错误、进程 id、包版本。
- WinINET、WinHTTP、环境变量代理快照与 `127.0.0.1:7897` 监听状态。
- Clash 连接日志中目标域名、规则、节点与失败原因，必要时脱敏。
- DNS 解析、IPv4/IPv6、TLS、WebSocket upgrade 和 HTTPS fallback 的分层结果。
- `git`/`curl` 对照探针，分别测试系统代理与显式代理。

### 成功标准

- 能稳定复现至少一种失败组合和一种成功对照组合。
- 能判断问题位于 Desktop 宿主、内置/外置 Codex client、系统代理继承、Clash 转发、WebSocket 路径或服务端中的哪一层。
- 给出不会依赖未文档化实验开关的稳定配置，或形成可提交给 OpenAI/Clash 的最小脱敏复现包。

## 八、证据位置

- Beacon 事件数据库：`<Beacon 数据目录>\runtime\state\platform.sqlite3`
- Codex Desktop 日志：`%LOCALAPPDATA%\Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\Local\Codex\Logs\<日期>\`
- Codex 配置：`%USERPROFILE%\.codex\config.toml`
- Beacon round-3 记录：`资源池/02_reference_docs/notes/20260712_beacon_round3_codex_activation_observations.txt`
- Beacon 30.8 实现记录：`资源池/自动化日志/20260713/macro-step30-8_codex-final-response-event-filtering/implementation-summary.md`

注意：后续共享或提交问题报告前，应移除 session id、request id、用户名、绝对项目路径、模型正文、token 统计和账号信息。
