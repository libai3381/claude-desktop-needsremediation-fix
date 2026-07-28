# claude-desktop-needsremediation-fix

*[English](README.md) | [简体中文](README.zh-CN.md)*

**先诊断，再修复。不要"卸载—重装—祈祷"。**
一个帮助 Claude Desktop Windows 用户诊断和修复更新失败、启动异常和环境兼容问题的开源工具，涵盖 MSIX/AppX、Code Integrity、WebView2、网络代理和系统兼容性问题。

A community toolkit to diagnose and recover Claude Desktop Windows failures caused by MSIX/AppX, Code Integrity, WebView2, network proxy, and system compatibility issues.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)
![Windows 10/11](https://img.shields.io/badge/Windows-10%20%2F%2011-0078D6)
![Unofficial](https://img.shields.io/badge/status-unofficial%20%2F%20community-orange)

> **本项目并非 Anthropic 官方项目。** 这是一个独立的、社区维护的项目，
> 与 Anthropic PBC 没有从属、认可或赞助关系。"Claude"和"Claude Desktop"
> 是 Anthropic 的商标，本仓库仅在描述兼容性时引用这些名称。
> 详见 [DISCLAIMER.md](DISCLAIMER.md)（英文）。

## 问题背景

Claude Desktop 装好后能用，但某个时刻突然坏掉：更新后无法启动、点击图标没反应、
登录页面一闪而过窗口就消失了，或者 Windows 提示应用"需要修复"而修复本身也失败。
Windows 自身的 MSIX/AppX 打包机制、Code Integrity（代码完整性校验）、WebView2、
你的网络/代理环境，以及（如果你用 Cowork）Hyper-V/HCS，任何一个环节都可能独立出问题，
而"重装、清缓存、重启电脑"这类通用建议根本不会告诉你到底是哪一环坏了。

**促成本项目的那个案例：** 一次被完整复现的排查记录——Claude Desktop 的 MSIX 软件包
在首次启动后悄悄变成 `Modified, NeedsRemediation`，根因被定位到 Windows Code Integrity
拦截了软件包自带的一个 DLL，并与四个独立提交的上游 bug 报告交叉核实，最终找到了
确认有效的修复方法。完整记录见：
[docs/known-issues/needsremediation-codeintegrity-vk_swiftshader.md](docs/known-issues/needsremediation-codeintegrity-vk_swiftshader.md)（英文）。

## 快速开始

```powershell
git clone https://github.com/libai3381/claude-desktop-needsremediation-fix.git
cd claude-desktop-needsremediation-fix
.\scripts\diagnose.ps1
```

输出示例：

```text
Claude Desktop Windows Diagnostic
==================================

Tier A - NeedsRemediation / CodeIntegrity case
  [Fail] Claude package status
         Status: Modified, NeedsRemediation (Version 1.24012.9.0)
         -> See docs/known-issues/needsremediation-codeintegrity-vk_swiftshader.md
  [Fail] CodeIntegrity Event 3010 (CodeIntegrity.cat)
         Found within the last 2 hours: 7/28/2026 5:41:03 PM
  [Fail] CodeIntegrity Event 3033 (signing level rejected)
         Found within the last 2 hours: 7/28/2026 5:41:03 PM - references vk_swiftshader.dll
  [Fail] AppModel-Runtime Event 6 (0x3CFC)
         Found within the last 2 hours: 7/28/2026 5:41:04 PM

...

Verdict:
  HIGH CONFIDENCE MATCH: this looks like the CodeIntegrity/vk_swiftshader.dll
  NeedsRemediation case. Confirmed fix: reinstall using
  ".\ClaudeSetup.exe --exe" (verify signature first). Details:
  docs/known-issues/needsremediation-codeintegrity-vk_swiftshader.md
```

脚本是**只读的**——只检查软件包状态、Windows 事件日志、服务和注册表配置，
不会安装、卸载、重启服务，也不会写入任何内容。

## 检查项一览

| 层级 | 检查项 | 用于捕获 |
|---|---|---|
| A | Claude 软件包状态 | `Modified`/`NeedsRemediation` 状态 |
| A | Code Integrity 事件 3010 / 3033 | `CodeIntegrity.cat` 缺失、DLL 签名级别不满足 |
| A | AppModel-Runtime 事件 6 | 由上述问题引发的 `0x3CFC` 启动阻塞 |
| B | 操作系统版本/构建/版本号 | 兼容性问题（例如 Cowork 需要专业版/企业版） |
| B | AppX 服务（`AppXSvc`、`ClipSVC`、`StateRepository`） | 应用部署框架异常 |
| B | WebView2 运行时 | 缺失或版本过旧 |
| B | 代理配置（WinINet vs WinHTTP） | 代理环境下静默的安装/更新失败 |
| B | 虚拟化 / HCS（`vmcompute`） | Cowork 相关的虚拟机启动问题 |
| B | 残留的 `Claude.exe` 进程 | 重装时文件被占用导致的错误 |

完整参考文档（英文）：[docs/error-codes.md](docs/error-codes.md) ·
[docs/architecture.md](docs/architecture.md) · [docs/faq.md](docs/faq.md)

## 已确认有效的修复方法（针对 NeedsRemediation/CodeIntegrity 这个案例）

```powershell
.\ClaudeSetup.exe --exe
```

以传统（非 MSIX）模式安装 Claude Desktop，绕开发生这个特定 bug 的
Code Integrity/AppModel 路径。这是一个**官方安装器未公开文档的参数**——
使用前请先验证安装器的数字签名（签名者应为 `Anthropic, PBC`），
更多注意事项见完整记录：
[docs/known-issues/needsremediation-codeintegrity-vk_swiftshader.md](docs/known-issues/needsremediation-codeintegrity-vk_swiftshader.md#verify-before-you-run-anything)（英文）。

## 路线图

- [x] **第一阶段** — README、已知问题文档、只读的 `diagnose.ps1`
- [ ] **第二阶段** — 分级自动修复脚本（`fix.ps1`），默认 dry-run，只执行安全操作
- [ ] **第三阶段** — 社区共建的已知问题数据库，通过 issue 模板结构化提交

本项目刻意先只发布第一阶段（纯只读）——如果你想帮忙一起设计第二阶段的安全边界，
欢迎看看 [CONTRIBUTING.md](CONTRIBUTING.md)（英文）。

## 参与贡献

- 遇到了匹配的案例或者新案例？[提交一个已知问题](.github/ISSUE_TEMPLATE/known_issue_submission.yml)。
- 遇到故障需要帮助？[提交诊断报告](.github/ISSUE_TEMPLATE/diagnostic_report.yml)，附上 `diagnose.ps1 -Json` 的输出。
- **发布任何内容前请先脱敏** —— 具体标准见 [CONTRIBUTING.md](CONTRIBUTING.md#before-you-post-anything)（英文）。

## 许可证

[MIT](LICENSE)。商标/从属关系声明见 [DISCLAIMER.md](DISCLAIMER.md)（英文）。
