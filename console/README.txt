Codex Proxy Assistant · 控制台版 0.1.3
========================================

用途：
帮助 Windows 10/11 用户检查 Codex、系统代理和 respect_system_proxy 配置，
缓解开启 VPN/代理后 Codex 频繁重连的问题。

最简单的使用方法：
1. 完整解压本压缩包。
2. 双击“启动修复.cmd”。
3. 先选择“自动检测并查看建议”。
4. 环境符合条件时，先“预览持久修复”，再“应用持久修复”。
5. 完全退出并重新打开 Codex。

程序不会：
- 修改 Windows 系统代理、VPN、证书、DNS 或防火墙；
- 修改 Codex 安装目录；
- 在无参数启动时直接写入配置；
- 自动发送会消耗额度的真实 Codex 请求。

“验证实际连接”只有在你输入 TEST 明确确认后才会发送最小请求，
并可能消耗少量 Codex 额度。

“临时 CLI 试运行”只影响新打开的 CLI 窗口，关闭窗口后失效，
不会修改持久配置。该功能需要已安装 Codex CLI。

默认配置路径：%USERPROFILE%\.codex\config.toml
配置快照目录：%USERPROFILE%\.codex\proxy-config-snapshots

完整说明与命令行参数请查看 README.md。
