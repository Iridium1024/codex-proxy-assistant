# Codex Proxy Assistant Console

一个面向 Windows 10/11 的轻量脚本工具：自动识别 Codex 与 Windows 系统代理，帮助缓解开启 VPN/代理后 Codex 频繁重连的问题。

这是与图形程序分开提供的控制台版本，也是面向大多数用户的推荐版本。运行时仅包含 CMD、PowerShell 脚本和说明文件，不需要 Python、PyQt5、PyInstaller，也没有 EXE。

## 下载与使用

1. 下载 `CodexProxyAssistant-Console-v0.1.3.zip` 并完整解压。
2. 在解压后的第一层双击 `启动修复.cmd`。
3. 先选择“自动检测并查看建议”。
4. 环境符合条件时，选择“预览持久修复”。
5. 确认内容后选择“应用持久修复”，并输入 `Y`。
6. 完全退出并重新打开 Codex，再观察连接情况。

无参数启动只进入菜单并执行只读检测，**不会自动写入配置**。

## 菜单功能

| 菜单 | 作用 |
| --- | --- |
| 自动检测并查看建议 | 检测 Desktop/CLI、系统代理、HTTPS 链路、配置与快照 |
| 预览持久修复 | 展示修改目标、前后状态、警告和阻止条件，不写文件 |
| 应用持久修复 | 创建快照后启用 `respect_system_proxy`，写入后由 Codex 验证，失败自动回滚 |
| 临时 CLI 试运行 | 只为新 CLI 窗口注入代理环境变量，关闭窗口后失效 |
| 验证实际连接 | 明确确认后发送一个最小、无工具的临时请求，可能消耗少量额度 |
| 恢复配置快照 | 从成功的应用快照恢复；恢复前会再创建安全快照 |
| 高级设置 | 手工选择 Codex 路径或输入代理地址 |

## 工具会修改什么

只有在用户确认后，工具才可能修改 Codex 用户配置：

```toml
[features]
respect_system_proxy = true
```

默认配置文件为 `%USERPROFILE%\.codex\config.toml`；如果设置了 `CODEX_HOME`，则使用该目录下的 `config.toml`。

工具不会修改：

- Windows 系统代理或 VPN 配置；
- 证书、DNS、防火墙或 WinHTTP；
- Codex 安装文件；
- 用户登录信息或 API Token。

## 支持范围

正式支持：

- Windows 10 22H2、Windows 11，x64；
- Windows PowerShell 5.1；
- Microsoft Store Codex Desktop、npm/PATH Codex CLI；
- Windows 手工 HTTP/HTTPS 系统代理；
- Clash/Mihomo/V2RayN 的 HTTP 或 Mixed 本地端口；
- 普通用户权限、中文或带空格的路径。

有限支持：

- PAC/WPAD：可以识别，但静态 HTTPS 测试不适用，由 Codex 运行时解析；
- SOCKS-only：可以识别并用于有限的临时 CLI 试运行，持久修复建议改用 HTTP/Mixed 端口；
- 带认证代理、ARM64、企业策略环境和非标准安装方式尚未完成完整验证。

系统缺少 `curl.exe` 时，工具只会报告“端口已开放但未完成 HTTPS 验证”，不会把它误报为代理可用。

## 命令行用法

普通用户只需双击 `启动修复.cmd`。熟悉 PowerShell 的用户也可以运行：

```powershell
# 结构化只读检测
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CodexProxyAssistant.ps1 -Action detect -Json

# 预览
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CodexProxyAssistant.ps1 -Action plan

# 非交互应用必须显式添加 -Yes
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CodexProxyAssistant.ps1 -Action apply -Yes

# 列出快照
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CodexProxyAssistant.ps1 -Action list-snapshots -Json

# 恢复指定快照
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CodexProxyAssistant.ps1 -Action restore -SnapshotId '<snapshot-id>' -Yes

# 真实连接验证可能消耗少量额度，必须显式添加 -Yes
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CodexProxyAssistant.ps1 -Action test-connection -Yes
```

可选参数：

- `-CodexPath`：手工指定 `.exe`、`.cmd` 或 `.bat`；
- `-ProxyEndpoint`：手工指定代理，例如 `http://127.0.0.1:XXXX`（将 `XXXX` 替换为实际端口）；
- `-ConfigPath`：供高级用户指定其他 Codex 配置文件；
- `-Json`：将非交互操作输出为 JSON。

## 快照与回滚

快照默认位于配置同级的 `proxy-config-snapshots` 目录。快照包含修改前的完整配置，可能含有敏感内容，请像保护原配置一样保护该目录。

写入过程采用同目录临时文件和替换操作；本地解析或 Codex 读取验证失败时，会自动恢复修改前内容。

## 从源码打包

```powershell
# 生成无外层套娃目录的发布 ZIP 和 SHA-256
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\package_release.ps1
```

## 许可证

本项目采用 [MIT License](LICENSE)。
