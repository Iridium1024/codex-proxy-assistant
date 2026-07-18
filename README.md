# Codex Proxy Assistant

一个面向 Windows 10/11 的轻量工具：自动识别 Codex 与系统代理，帮助缓解开启 VPN/代理后 Codex 频繁重连的问题。

它只在你确认后修改 Codex 用户配置；不会修改 Windows 代理、VPN、证书、DNS、防火墙或 Codex 安装文件。

## 下载哪个版本？

前往 [Releases](https://github.com/Iridium1024/codex-proxy-assistant/releases/latest) 下载：

| 版本 | 下载文件 | 适合人群 |
| --- | --- | --- |
| **PowerShell 文字窗口版（推荐）** | `CodexProxyAssistant-Console-v0.1.3.zip` | 适合大多数用户；界面轻量、步骤清楚，无需安装 Python，也不依赖图形运行库 |
| GUI 图形版 | `CodexProxyAssistant-v0.1.3-windows-x64.zip` | 偏好鼠标操作、输入框和可视化状态反馈的用户 |
| 单文件 CMD 版 | `codex-vpn-repair.cmd` | 熟悉命令行、希望只下载一个文件并快速运行的用户 |

`CodexProxyAssistant-v0.1.3-minimal.zip` 是只保留 GUI 必需运行文件的精简包，功能与完整 GUI 包一致，但不附带 README 和单文件 CMD。`SHA256SUMS.txt` 用于校验所有发布附件。

三类版本共用同一套 PowerShell 核心逻辑，主要区别只在交互方式和分发形式。综合易用性、兼容性与体积，建议大多数用户优先下载 **PowerShell 文字窗口版**。

## PowerShell 文字窗口版使用方法

1. 完整解压 `CodexProxyAssistant-Console-v0.1.3.zip`。
2. 双击解压目录第一层的 `启动修复.cmd`。
3. 先选择“自动检测并查看建议”，再按提示预览、应用或验证。
4. 修复后完全退出并重新打开 Codex。

无参数启动只会进入中文菜单并执行只读检测，不会自动修改配置。

## 图形程序使用方法

1. 完整解压 ZIP；解压后的第一层即可看到 `CodexProxyAssistant.exe`。
2. 打开程序，等待自动检测完成。
3. 查看“当前目标”“系统代理”“Codex 配置”和“下一步”提示。
4. 点击“预览修改”，确认后点击“应用持久修复”。
5. 完全退出并重新启动 Codex。
6. 如需撤销，选择“配置快照”并点击“恢复所选快照”。

程序会分别显示：

- 当前检测的是 Codex Desktop 还是 CLI；
- 代理端口是否开放，以及是否真的可以访问 HTTPS；
- 配置是否无需修改、可以修复或需要人工检查；
- 推荐的下一步。

“验证实际连接”只在你主动确认后发送一个最小临时请求，会使用当前 Codex 登录状态，并可能消耗少量额度。自动检测和应用修复不会发送该请求。

“临时 CLI 试运行”只为新启动的 CLI 进程设置代理，关闭控制台后失效，不写入持久配置。

## 单文件 CMD 使用方法

双击 `codex-vpn-repair.cmd` 可进入检测与修复流程，也可在终端运行：

```bat
codex-vpn-repair.cmd status
codex-vpn-repair.cmd repair --dry-run
codex-vpn-repair.cmd repair
codex-vpn-repair.cmd restore
```

该 CMD 是从与 GUI 相同的核心代码自动生成的单文件版本，不依赖 Python 或第三方模块。

## 支持范围

正式支持目标：

- Windows 10 22H2、Windows 11，x64；
- Windows PowerShell 5.1；
- Microsoft Store Codex Desktop、npm/PATH Codex CLI；
- Windows 手工 HTTP/HTTPS 系统代理；
- Clash/Mihomo/V2RayN 的 HTTP 或 Mixed 本地端口；
- 普通用户权限，以及中文或带空格的路径。

有限支持：

- PAC/WPAD：能够识别，但静态 HTTPS 端点测试不适用，由 Codex 运行时解析；
- SOCKS-only：可识别并用于有限的临时测试，持久修复建议改用 HTTP/Mixed 端口；
- 带用户名或密码的代理 URL：当前不支持；
- ARM64、企业认证代理和非标准安装方式：尚未完成完整验证。

## 修复边界

工具会在修改前创建快照，原子写入配置，并让所选 Codex 再次读取配置；验证失败时自动恢复原内容。它不会承诺解决所有重连问题：账号状态、代理节点、规则分流、服务端状态、WebSocket 或 Desktop 附属连接仍可能造成独立故障。

默认配置文件为 `%USERPROFILE%\.codex\config.toml`。若设置了 `CODEX_HOME`，则使用该目录下的 `config.toml`。快照位于同级 `proxy-config-snapshots`，其中可能包含完整配置，请像保护原配置一样保护它。

## 许可证

本项目采用 [MIT License](LICENSE)。
