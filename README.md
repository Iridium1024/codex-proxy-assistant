# Codex Proxy Assistant

一个面向 Windows 10/11 的开源小工具，用于诊断 Codex、Windows 系统代理与 Codex 用户配置是否匹配，并缓解开启 VPN/系统代理后可能出现的频繁重连问题。

工具只在用户确认后修改 Codex 用户配置，不会修改 Windows 代理、VPN、证书、DNS、防火墙或 Codex 安装文件。

## 应该下载哪个文件？

前往 [Releases](https://github.com/Iridium1024/codex-proxy-assistant/releases/latest) 下载：

| 文件 | 适合人群 | 说明 |
| --- | --- | --- |
| `CodexProxyAssistant-v0.5.2-windows-x64.zip` | 缺少相关经验的用户（推荐） | 完整免安装程序包。解压后第一层即可看到并运行 `CodexProxyAssistant.exe`。 |
| `CodexProxyAssistant-v0.5.2-minimal.zip` | 希望获得最小运行目录的用户 | 只包含 GUI 程序运行所必需的文件，解压后第一层即可看到 EXE。 |
| `codex-vpn-repair.cmd` | 熟悉命令行和配置文件的用户 | 单文件脚本，不依赖 Python 或第三方模块。 |
| `SHA256SUMS.txt` | 需要校验下载完整性的用户 | 包含所有发布文件的 SHA-256。 |

> 如果不熟悉 Codex 配置、系统代理或命令行，请使用完整程序压缩包。熟悉相关内容的用户可以直接下载并运行 CMD 脚本。

## 图形程序使用方法

1. 完整解压 `CodexProxyAssistant-v0.5.2-windows-x64.zip`；解压后的第一层即可看到 `CodexProxyAssistant.exe`，不要只把 EXE 单独拖出压缩包。
2. 打开 `CodexProxyAssistant.exe`。程序启动后会自动读取 Codex、系统代理和配置状态。
3. 检查自动识别的 Codex 路径与系统代理；如有需要，可手动选择或输入后重新检测。
4. 点击“预览修改”查看计划。此步骤不会写入文件。
5. 点击“应用持久修复”，程序会先创建配置快照，再写入并验证：

   ```toml
   [features]
   respect_system_proxy = true
   ```

6. 完全退出并重新启动 Codex。需要撤销时，在“配置快照”中选择记录并点击“恢复所选快照”。

“临时代理试运行（CLI）”只为新启动的 Codex CLI 进程设置代理环境变量，退出该控制台后自动失效，不会改动持久配置。

## CMD 脚本使用方法

直接双击 `codex-vpn-repair.cmd` 会进入检测与修复流程。也可以在命令提示符或 PowerShell 中运行：

```bat
codex-vpn-repair.cmd status
codex-vpn-repair.cmd repair --dry-run
codex-vpn-repair.cmd repair
codex-vpn-repair.cmd restore
```

- `status`：只检查状态。
- `repair --dry-run`：预览将执行的操作。
- `repair`：创建备份后应用配置。
- `restore`：恢复脚本创建的备份。
- `--no-pause`：结束时不等待按键，适合自动化调用。

## 主要功能

- 自动检测 PATH、常见安装目录和 Microsoft Store/桌面包中的 Codex 引擎。
- 仅选择能够通过 `features list` 确认支持 `respect_system_proxy` 的 Codex 版本执行持久修改。
- 读取 Windows 当前用户的手工代理、PAC 或自动发现状态，但不改写系统代理。
- 修改前创建带时间、哈希、版本和结果信息的配置快照。
- 支持预览、持久修复、快照恢复和临时 CLI 代理试运行。
- 对重复 `[features]`、重复键和无法识别的值采取保守处理，不覆盖不安全配置。

## 配置与快照位置

默认配置文件：

```text
%USERPROFILE%\.codex\config.toml
```

如果设置了 `CODEX_HOME`，则使用该目录下的 `config.toml`。配置快照保存在配置文件同级的 `proxy-config-snapshots` 目录。

快照为了可靠恢复会保存完整配置。如果配置中含有敏感信息，请像保护原配置一样保护快照目录。

## 边界与安全说明

- `respect_system_proxy` 是否可用取决于所安装的 Codex 版本；工具会在修改前和修改后调用 Codex 自身进行验证。
- 工具不会保证解决所有重连问题。PAC/WPAD、代理软件转发、WebSocket、认证和附属服务都可能形成独立故障路径。
- 手工代理输入不接受包含用户名或密码的 URL。
- 临时模式面向 Codex CLI，不能向已经运行的桌面应用注入环境变量。
- 建议先使用“预览修改”或 CMD 的 `--dry-run`。

## 从源码构建

需要 Python 3.11 和 Windows PowerShell：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\setup_env.ps1
powershell.exe -ExecutionPolicy Bypass -File .\scripts\build_release.ps1 -CleanWorkspace
```

生成 GitHub 发布包：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\package_github_release.ps1 -Version 0.5.2
```

核心与 GUI 测试：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tests\test_core.ps1
$env:QT_QPA_PLATFORM = 'offscreen'
python -m unittest discover -s .\tests -p 'test_*.py' -v
```

## 许可证

本项目采用 [MIT License](LICENSE)。
