# Codex Desktop 网络稳定性工具——前期调查与实现建议

> 文档定位：供 Codex 在正式编码前阅读，用于明确问题背景、现有开源实现、差异化方向、MVP 边界、安全约束和验收标准。<br>
> 调查快照日期：2026-07-13<br>
> 建议状态：前期调查稿，不作为最终需求规格书。

---

## 1. 调查目标

拟评估并实现一个面向 Codex Desktop 的轻量级网络诊断与修复工具，用于处理 Windows 等环境下开启 VPN、Clash/Mihomo、V2RayN 或其他本地代理后出现的以下问题：

- Codex Desktop 频繁显示 `Reconnecting...`；
- 长时间停留在“思考中”或首轮响应迟迟不开始；
- 流式输出中途断开；
- 出现 `TLS EOF`、`tls handshake eof`、`stream disconnected before completion`；
- 浏览器或终端可以联网，但 Codex Desktop 或其 app-server 子进程未继承代理；
- 全局代理模式正常，规则代理模式异常；
- 切换代理节点后，新会话或既有会话无法稳定恢复。

本项目的核心目标不是代理服务本身，而是：

> 对 Codex Desktop 的网络链路进行可解释诊断，并以最小权限、可预览、可备份、可回滚的方式修复代理继承与路由一致性问题。

---

## 2. 初步问题判断

Codex Desktop 的 `Reconnecting...` 并不对应单一故障，至少可能包括：

1. 本地代理端口未启动或端口填写错误；
2. 端口可建立 TCP 连接，但不支持 HTTP CONNECT；
3. Windows 系统代理已启用，但 Codex 进程未继承 `HTTP_PROXY`、`HTTPS_PROXY` 等环境变量；
4. Codex Desktop 启动的 app-server 或其他子进程未继承代理；
5. Clash/Mihomo 规则模式将不同 OpenAI 域名分流到不同出口；
6. OpenAI 专用策略组固定在失效节点，而默认策略组选中了有效节点；
7. 代理对 WebSocket/WSS、长连接或流式响应支持不稳定；
8. DNS 在本地解析失败，但通过代理远程解析可以成功；
9. Codex 配置文件仍保留旧端口、旧 provider 或失效设置；
10. 网络链路正常，但 Codex Desktop 自身存在首轮会话状态初始化或界面同步问题。

因此，本项目不能把所有 `Reconnecting...` 都解释成“代理未设置”，也不应默认通过修改系统代理来处理。

---

## 3. 已发现的开源项目

### 3.1 catmanmx/codex-desktop-proxy-launcher

仓库：

https://github.com/catmanmx/codex-desktop-proxy-launcher

定位：

- Windows 下的 Codex Desktop 专用代理启动器；
- 为 Codex 进程注入固定的本地代理入口；
- 尽量不修改 Windows 系统代理，不影响浏览器、Git、npm 等其他程序；
- 支持代理端口测试、节点稳定性检测、开机启动和日志健康检查。

主要价值：

- 处理 Codex Desktop 及 app-server 未稳定继承代理的问题；
- 本地代理端口不变时，用户可在代理软件中切换远端节点；
- 产品化程度高于单纯说明文档。

主要局限：

- Windows 优先；
- 将代理启动、连接监测和日志数据库处理放在同一项目中，功能边界偏宽；
- 其“日志止血”功能与网络修复并非强相关，不适合作为本项目 MVP 的默认功能；
- 第三方 EXE 需要额外的供应链信任，源码运行和可复现构建更重要。

### 3.2 baixinpan/codex-reconnecting-doctor

仓库：

https://github.com/baixinpan/codex-reconnecting-doctor

定位：

- Codex Skill/Plugin 与 Python 诊断脚本；
- 检查代理环境变量、Codex provider、本地代理端口和 HTTPS CONNECT；
- 支持只读诊断、JSON 报告、`--dry-run`、配置备份和修复；
- 可检查当前 provider 是否可能需要关闭 WebSocket。

主要价值：

- 默认先报告后修改；
- 会实际验证代理端口，而不是仅判断端口是否监听；
- 安全边界和可回滚意识较好；
- 可作为本项目诊断逻辑的直接竞品参考。

主要局限：

- 项目规模较小，社区验证有限；
- 对 Windows Desktop 的专用启动链路覆盖不如专用启动器；
- `supports_websockets = false` 不是所有 ChatGPT 登录和 provider 配置下都可用；
- 诊断深度尚不足以完整区分规则分流、节点一致性和 Codex 内部状态问题。

### 3.3 moneycat957/codex-desktop-reconnecting-fix

仓库：

https://github.com/moneycat957/codex-desktop-reconnecting-fix

定位：

- 故障排查与配置建议文档；
- 建议设置用户级代理环境变量、减少启动同步功能、检查 WinHTTP；
- 提供 HTTP/SSE provider 的备选配置。

主要价值：

- 总结了 Windows 环境中常见的代理继承问题；
- 适合作为人工排查清单。

主要局限：

- 更接近说明文档，不是完整工具；
- `setx` 会修改用户级环境变量，影响范围大于进程级注入；
- 关闭 WebSocket 的 provider 方案可能遇到 API scope 不足；
- 不应直接照搬其所有设置。

### 3.4 howtimeschange/fix-codex-reconnecting-skill

仓库：

https://github.com/howtimeschange/fix-codex-reconnecting-skill

定位：

- 轻量 Codex Skill；
- 检测本地代理端口；
- 更新 `~/.codex/.env`；
- 必要时建议使用 HTTP/SSE。

主要价值：

- 结构轻量；
- 可直接通过 Codex Skill 使用。

主要局限：

- 功能和 `codex-reconnecting-doctor` 高度重合；
- 代码量和提交历史较少；
- 故障分类与可观测性有限。

---

## 4. 推广程度与竞争判断

截至本次调查，相关项目整体处于早期、小众状态：

- 多数仓库为单脚本、单 Skill 或配置说明；
- 可观察到的 Star 基本处于 0—1 量级；
- `codex-desktop-proxy-launcher` 的迭代和产品化程度相对较高，但尚无证据表明形成了成熟用户社区；
- 该方向已经证明存在真实需求，但尚未形成明确的头部项目。

注意：

- Star 数量会随时间变化；
- Codex 在正式形成竞品分析或 README 时，应使用 GitHub API/CLI 重新获取实时数据，例如：

```powershell
gh api repos/catmanmx/codex-desktop-proxy-launcher --jq "{stars:.stargazers_count,forks:.forks_count,updated:.updated_at}"
gh api repos/baixinpan/codex-reconnecting-doctor --jq "{stars:.stargazers_count,forks:.forks_count,updated:.updated_at}"
gh api repos/moneycat957/codex-desktop-reconnecting-fix --jq "{stars:.stargazers_count,forks:.forks_count,updated:.updated_at}"
gh api repos/howtimeschange/fix-codex-reconnecting-skill --jq "{stars:.stargazers_count,forks:.forks_count,updated:.updated_at}"
```

综合判断：

> 这是一个低竞争、需求已被验证，但用户规模和长期维护价值仍需验证的轻量工具方向。

---

## 5. 官方问题证据

OpenAI Codex 官方仓库中存在与代理、WebSocket 和流式响应中断有关的问题报告。

重点参考：

### Windows + Clash Verge Rev 下流式响应中断

https://github.com/openai/codex/issues/18647

报告现象包括：

- `stream disconnected before completion`；
- `peer closed connection without sending TLS close_notify`；
- `tls handshake eof`；
- `error decoding response body`；
- 新窗口或新会话频繁重连。

该 issue 的后续经验表明：

- 全局代理模式可能正常；
- 规则模式可能因 OpenAI 专用策略组固定到失效节点而失败；
- 仅添加域名规则并不足够；
- Codex、OpenAI、ChatGPT 和 WSS 相关流量应尽量保持出口路径一致。

### 流式请求断开

https://github.com/openai/codex/issues/10985

### 首轮界面显示重连，但 app-server 未真正断开

https://github.com/openai/codex/issues/18471

该类报告说明：

> 某些 `Reconnecting...` 可能属于会话状态或界面同步问题，而非真实网络断线。工具应在网络检查全部通过后明确标记“疑似 Codex 内部状态问题”，而不是继续修改代理。

---

## 6. 建议项目定位

不建议再实现一个单纯的“设置环境变量并启动 Codex”脚本。

建议定位为：

> Codex Desktop 网络链路诊断、进程级代理启动与稳定性监测工具。

候选项目名：

- `codex-netguard`
- `codex-connect-doctor`
- `codex-proxy-inspector`
- `codex-link-guardian`

最终命名应在创建仓库前检索 GitHub 和 PyPI，避免重名或过度接近现有项目。

---

## 7. 目标用户

首个版本优先面向：

- Windows 10/11；
- Codex Desktop；
- Clash Verge Rev、Mihomo、V2RayN 等本地代理；
- 使用 HTTP 或 Mixed 本地端口；
- 能正常登录 Codex，但存在反复重连或流式响应中断；
- 不希望修改全局系统代理；
- 希望获得可读诊断报告而不是盲目“一键修复”的用户。

跨平台支持可以在 Windows MVP 稳定后再扩展。

---

## 8. MVP 功能范围

### 8.1 只读诊断

命令示例：

```powershell
codex-netguard diagnose
codex-netguard diagnose --json
```

检查内容：

1. Codex Desktop 是否安装、是否正在运行；
2. Codex 及 app-server 相关进程；
3. 常见本地代理端口是否监听；
4. 代理端口是否支持 HTTPS CONNECT；
5. 直连与代理访问 OpenAI/ChatGPT 相关端点的差异；
6. 当前进程、用户级和 `~/.codex/.env` 中的代理变量；
7. `~/.codex/config.toml` 中当前 provider 及网络相关配置；
8. 系统代理和 WinHTTP 状态；
9. DNS、TLS、HTTPS 和长连接的基础检查；
10. Codex 日志中的典型错误关键词；
11. 生成脱敏的故障分类和建议。

### 8.2 修复预览

```powershell
codex-netguard repair --dry-run
```

要求：

- 显示拟修改文件；
- 显示修改前后差异；
- 不执行实际写入；
- 不显示 Token、Cookie、Authorization 等敏感内容。

### 8.3 最小修复

```powershell
codex-netguard repair --apply
```

仅允许：

- 备份并修复 `~/.codex/.env` 中明确失效的代理变量；
- 在用户明确选择时修复有限的 Codex 配置；
- 不修改 Windows 全局系统代理；
- 不修改证书；
- 不修改用户其他软件配置。

### 8.4 进程级代理启动

```powershell
codex-netguard launch --proxy auto
codex-netguard launch --proxy http://127.0.0.1:7890
```

要求：

- 只向新启动的 Codex 进程及其子进程注入代理环境变量；
- 不长期写入系统或用户级环境变量；
- 明确提示重启会中断现有任务；
- 记录使用的代理端口，但不记录认证密码。

### 8.5 基础稳定性监测

```powershell
codex-netguard monitor --duration 60
```

输出：

- 探测次数；
- 成功率；
- DNS、TCP、TLS、HTTP CONNECT 各阶段耗时；
- 失败类型；
- 节点切换前后的变化。

---

## 9. 暂不纳入 MVP 的功能

第一版不得默认实现：

- 自建代理、VPN 或流量转发服务；
- TLS 中间人、根证书安装或 HTTPS 解密；
- 抓取用户对话内容；
- 上传本地日志到远程服务器；
- 自动修改 Clash/Mihomo 配置；
- 自动切换代理节点；
- 修改 Codex 日志数据库；
- 创建阻断日志写入的数据库 trigger；
- 自动关闭大量 Codex 功能；
- 未经验证设置 `supports_websockets = false`；
- 需要管理员权限的系统级修改；
- 与网络诊断无直接关系的 Codex 账号、额度或模型管理。

---

## 10. 建议故障分类

工具至少应输出以下分类之一：

| 故障类别 | 核心证据 | 建议动作 |
|---|---|---|
| `PROXY_NOT_RUNNING` | 本地端口未监听 | 启动代理或修正端口 |
| `PROXY_PROTOCOL_MISMATCH` | TCP 可达但 HTTP CONNECT 失败 | 改用 HTTP/Mixed 端口 |
| `CODEX_PROXY_NOT_INHERITED` | 系统代理正常，但 Codex 环境缺少代理变量 | 使用进程级代理启动 |
| `STALE_CODEX_ENV` | `.env` 指向已关闭或旧端口 | 备份后更新 `.env` |
| `RULE_ROUTING_INCONSISTENT` | 全局模式正常、规则模式失败或相关域名出口不一致 | 检查代理策略组 |
| `UNSTABLE_PROXY_NODE` | 连续探测出现高失败率/TLS EOF | 切换稳定节点 |
| `WEBSOCKET_UNSTABLE` | HTTPS 正常，WSS/长连接持续失败 | 检查节点与代理协议；谨慎评估 HTTP/SSE |
| `DNS_PATH_FAILURE` | 本地解析失败，代理远程解析正常 | 使用支持远程 DNS 的代理模式 |
| `CODEX_CONFIG_CONFLICT` | provider、base URL 或网络设置冲突 | 给出配置差异和回滚方案 |
| `LIKELY_CODEX_INTERNAL_STATE` | 网络检查全部通过，但首轮仍显示重连 | 停止自动修复，建议更新/重启并报告 issue |
| `UNKNOWN` | 证据不足 | 输出完整脱敏报告，不进行写操作 |

---

## 11. 安全设计原则

### 默认只读

未出现 `--apply` 或明确用户授权时，任何文件和系统设置都不得修改。

### 最小权限

优先采用进程级环境变量，不修改：

- Windows 系统代理；
- WinHTTP；
- 注册表；
- 根证书；
- 防火墙；
- 其他软件配置。

### 自动备份

修改任何文件前：

- 创建时间戳备份；
- 输出备份路径；
- 提供回滚命令；
- 验证修改后文件仍可解析。

### 敏感信息脱敏

报告中需要遮蔽：

- API Key；
- Token；
- Authorization；
- Cookie；
- 带用户名和密码的代理 URL；
- 可能包含隐私的完整用户目录；
- 对话正文。

### 可复现构建

发布的 EXE 应由 GitHub Actions 从公开源码构建，并同时提供：

- SHA-256；
- 源码版本号；
- 构建日志；
- Release notes；
- 软件物料或依赖清单（条件允许时）。

---

## 12. 建议技术路线

### 核心语言

建议采用 Python 3.11+：

- 网络和配置处理成本低；
- 易于编写单元测试；
- 可使用 PyInstaller 打包；
- 便于跨平台扩展。

### Windows 辅助层

必要时使用 PowerShell 负责：

- 查找 Codex Desktop 启动入口；
- 查询系统代理和 WinHTTP；
- 读取进程信息；
- 以新环境变量启动 Codex；
- 处理 WindowsApps 兼容问题。

### 初期不做复杂 GUI

第一版优先提供 CLI。

后续可增加简单 GUI/托盘，但 GUI 必须复用同一核心诊断模块，不能复制一套独立逻辑。

### 配置解析

- TOML：使用成熟 TOML 库；
- `.env`：保留未知行和注释，避免全文件重写；
- JSON：用于机器可读报告；
- 所有文件写入采用原子替换或安全临时文件策略。

---

## 13. 建议代码结构

```text
codex-netguard/
├─ src/
│  └─ codex_netguard/
│     ├─ cli.py
│     ├─ models.py
│     ├─ diagnostics/
│     │  ├─ process.py
│     │  ├─ proxy_ports.py
│     │  ├─ http_connect.py
│     │  ├─ dns_tls.py
│     │  ├─ websocket.py
│     │  ├─ codex_config.py
│     │  ├─ windows_proxy.py
│     │  └─ logs.py
│     ├─ classification/
│     │  └─ rules.py
│     ├─ repair/
│     │  ├─ plan.py
│     │  ├─ env_file.py
│     │  ├─ backup.py
│     │  └─ rollback.py
│     ├─ launcher/
│     │  └─ windows.py
│     └─ redaction.py
├─ tests/
│  ├─ unit/
│  ├─ fixtures/
│  └─ integration/
├─ scripts/
├─ docs/
│  ├─ architecture.md
│  ├─ troubleshooting.md
│  ├─ security.md
│  └─ competitor-notes.md
├─ .github/workflows/
├─ pyproject.toml
├─ README.md
├─ README.zh-CN.md
├─ SECURITY.md
├─ CONTRIBUTING.md
└─ LICENSE
```

---

## 14. Codex 实施阶段建议

### 阶段 0：仓库初始化

交付：

- `README`；
- `LICENSE`；
- `pyproject.toml`；
- 基础 CLI；
- 测试框架；
- GitHub Actions；
- 架构与安全说明。

不得实现自动修复。

### 阶段 1：只读代理诊断

交付：

- 常见端口扫描；
- TCP 检查；
- HTTP CONNECT 检查；
- 直连/代理对照；
- 文本与 JSON 报告；
- 脱敏模块。

### 阶段 2：Codex 配置和进程诊断

交付：

- `.env` 和 `config.toml` 只读检查；
- Codex/app-server 进程识别；
- Windows 系统代理、用户环境变量和 WinHTTP 对照；
- 故障分类规则。

### 阶段 3：安全修复与回滚

交付：

- 修复计划；
- `--dry-run`；
- 自动备份；
- `.env` 的最小修改；
- 回滚；
- 修改后验证。

### 阶段 4：进程级代理启动

交付：

- 自动寻找 Codex 启动入口；
- 仅对 Codex 注入代理；
- 正常模式/代理模式启动；
- 不污染全局环境。

### 阶段 5：稳定性监测和发布

交付：

- 连续探测；
- 错误统计；
- PyInstaller；
- Release；
- SHA-256；
- 安装、卸载与故障排查文档。

每一阶段应保持可单独运行、可测试、可回滚，不得一次性堆入所有功能。

---

## 15. 测试矩阵

至少覆盖：

### 操作系统

- Windows 10；
- Windows 11；
- 后续可扩展 macOS、Linux、WSL。

### 代理状态

- 无代理；
- HTTP 端口；
- Mixed 端口；
- SOCKS-only 端口；
- 端口未启动；
- 端口已监听但无法访问外网；
- 节点高延迟；
- 节点间歇断开。

### 配置状态

- `.env` 不存在；
- `.env` 正确；
- `.env` 指向旧端口；
- `.env` 包含无关设置和注释；
- `config.toml` 正常；
- TOML 格式错误；
- provider 未配置；
- provider 明确禁用 WebSocket。

### 安全测试

- 日志中包含伪造 API Key；
- 代理 URL 含用户名密码；
- 文件只读；
- 备份失败；
- 写入中断；
- 回滚；
- 重复执行修复命令的幂等性。

---

## 16. MVP 验收标准

项目达到 MVP 至少应满足：

1. 不设置代理时，能够明确报告当前直连状态；
2. 能发现常见的 HTTP/Mixed 本地代理端口；
3. 能区分“端口开放”和“可完成 HTTPS CONNECT”；
4. 能检查 Codex `.env` 是否指向过期端口；
5. 能生成不包含敏感信息的 JSON 报告；
6. 默认执行不修改任何文件；
7. `--dry-run` 显示准确差异；
8. 正式修改前自动备份；
9. 能恢复修改前配置；
10. 能以进程级代理环境启动 Codex；
11. 不修改 Windows 系统代理；
12. 所有核心模块有单元测试；
13. GitHub Actions 能完成测试和构建；
14. README 能让普通用户在十分钟内完成诊断；
15. 对网络全部正常但仍重连的情况，不进行无依据自动修复。

---

## 17. 项目经历价值

项目完成后可以体现：

- 对真实网络故障的分层定位；
- HTTP CONNECT、TLS、WebSocket 和流式连接理解；
- Windows 进程及环境变量管理；
- 配置解析、最小修改和回滚；
- 安全、隐私和供应链设计；
- CLI 产品设计；
- 自动化测试和 GitHub Actions；
- 开源文档和 Release 管理；
- 使用 Codex 推进受控软件工程工作的能力。

简历描述参考：

> 针对 Codex Desktop 在 VPN 及规则代理环境下出现的 WebSocket 重连、TLS 中断和代理继承失效问题，设计并实现诊断优先、配置可回滚的网络稳定性工具；支持代理端口发现、HTTP CONNECT 与长连接测试、Codex 子进程代理继承检查、配置脱敏分析、进程级代理启动及连续可用性监测，并通过 GitHub Actions 完成自动测试和可复现发布。

---

## 18. Codex 开工约束

Codex 在正式编码前应遵守：

1. 先阅读本文档和现有竞品源码；
2. 不直接复制现有项目代码；
3. 如参考具体实现，确认许可证并在文档中记录来源；
4. 先完成阶段 0 和阶段 1，不得直接开发“一键修复”；
5. 所有修复均先实现 `dry-run`；
6. 所有日志和报告必须经过脱敏；
7. 不安装证书、不抓包解密、不上传数据；
8. 不修改系统代理和注册表；
9. 不读取 Codex 对话正文；
10. 每一阶段提交测试、文档和明确的验收结果；
11. 对不确定的 Codex 私有实现不得猜测，应基于可观察行为和公开配置工作；
12. 遇到 Codex 版本差异时，优先增加兼容性检测，不应硬编码单一版本路径。

---

## 19. 建议的 Codex 首轮任务

```text
阅读 docs/前期调查与实现建议.md，完成项目阶段0，不实现任何自动修复功能。

目标：
1. 初始化 Python 3.11+ 项目和 CLI；
2. 建立 src-layout、pytest、ruff 和类型检查；
3. 定义诊断结果、故障分类和修复计划的数据结构；
4. 实现统一的敏感信息脱敏模块及其测试；
5. 创建 README、SECURITY、CONTRIBUTING、架构文档；
6. 配置 GitHub Actions 执行 lint、type-check 和 tests；
7. 提供阶段1的实现计划和接口设计。

约束：
- 不修改本机 Codex 配置；
- 不扫描或读取用户对话正文；
- 不访问或输出 Token；
- 不修改系统代理；
- 不引入 GUI；
- 不复制竞品代码；
- 任何外部实现参考均记录仓库、文件和许可证；
- 完成后运行全部检查，并以“改动、测试结果、未完成项、下一阶段建议”格式汇报。
```

---

## 20. 关键链接汇总

### 竞品与相关工具

- https://github.com/catmanmx/codex-desktop-proxy-launcher
- https://github.com/baixinpan/codex-reconnecting-doctor
- https://github.com/moneycat957/codex-desktop-reconnecting-fix
- https://github.com/howtimeschange/fix-codex-reconnecting-skill

### OpenAI Codex 官方仓库与问题

- https://github.com/openai/codex
- https://github.com/openai/codex/issues/18647
- https://github.com/openai/codex/issues/10985
- https://github.com/openai/codex/issues/18471

---

## 21. 最终调查结论

该项目具备立项价值，理由如下：

- 存在真实且可复现的用户痛点；
- 官方仓库中已有相关连接问题报告；
- 当前第三方项目普遍轻量、社区较小，尚无明显头部实现；
- MVP 技术难度可控，适合由 Codex 在明确边界下协助实现；
- 通过安全诊断、故障分类、进程级代理启动、规则一致性提示和可复现发布，可以形成相对明确的差异化；
- 即使项目最终 Star 数量有限，也能作为完整工程项目展示问题分析、实现、测试、安全和开源维护能力。

立项前仍需确认：

1. 项目名称是否冲突；
2. Windows Codex Desktop 的实际启动入口和子进程结构；
3. 首批测试所用代理客户端及端口；
4. 是否仅面向 ChatGPT 登录模式；
5. 第一版是否只支持 HTTP/Mixed 代理；
6. 是否准备公开收集脱敏诊断报告以完善规则；
7. 维护周期和支持范围。
