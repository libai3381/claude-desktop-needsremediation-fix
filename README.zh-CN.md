# claude-desktop-needsremediation-fix

*[English](README.md) | [简体中文](README.zh-CN.md)*

**先诊断，再修复。不要"重装了就祈祷"。**
一个开源工具，帮助你诊断并修复 Claude Desktop 在 Windows 上因 MSIX/AppX、
Code Integrity、WebView2、网络代理等环境兼容问题导致的更新失败、启动异常等故障。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)
![Windows 10/11](https://img.shields.io/badge/Windows-10%20%2F%2011-0078D6)
![Unofficial](https://img.shields.io/badge/status-unofficial%20%2F%20community-orange)

> **本项目并非 Anthropic 官方项目。** 这是一个独立的、社区维护的项目，
> 与 Anthropic PBC 没有从属、认可或赞助关系。"Claude"和"Claude Desktop"
> 是 Anthropic 的商标，本仓库仅在描述兼容性时引用这些名称。
> 详见 [DISCLAIMER.md](DISCLAIMER.md)（英文）。

## 核心案例

**根因：** Windows Code Integrity（代码完整性校验）拦截了 Claude Desktop
MSIX 软件包自带的一个 DLL（`vk_swiftshader.dll`），因为该软件包没有携带
可用的完整性目录。应用在第一次渲染页面时崩溃，Windows 随后把它永久标记为
`Modified, NeedsRemediation`。

**已确认有效的修复方法：**

```powershell
.\ClaudeSetup.exe --exe
```

以传统（非 MSIX）模式重新安装 Claude Desktop，彻底绕开发生这个 bug 的路径。
这是一个官方安装器未公开文档的参数——使用前请先验证安装器的数字签名
（签名者应为 `Anthropic, PBC`）。完整日志证据和注意事项见：
[docs/known-issues/needsremediation-codeintegrity-vk_swiftshader.md](docs/known-issues/needsremediation-codeintegrity-vk_swiftshader.md)（英文）。

不想手动操作？[`scripts/fix-needsremediation.ps1`](scripts/fix-needsremediation.ps1)
把上面这几步自动化了——检测、确认、下载、验证签名、执行，如果你的情况不是
一个确认匹配的案例，它会直接拒绝往下走。它不会开启开发者模式，也不会绕过
MSIX 签名校验。具体做了什么、不会做什么，见
[scripts/README.md](scripts/README.md#fix-needsremediationps1)（英文）。

**你遇到的是不是这种情况？**

- 更新后无法启动
- 点击图标没有任何反应
- 登录页面一闪而过，窗口随后消失
- Windows 提示应用"需要修复"——而修复本身也失败

如果是，往下运行 `diagnose.ps1` 确认一下，然后直接用上面的修复方法。
如果你的症状不太一样（代理报错、WebView2 问题、Cowork/虚拟化相关问题），
下面更全面的检查项也覆盖了这些。"重装、清缓存、重启电脑"这类通用建议
不会告诉你到底是哪一环坏了，但这个工具会。

## 快速开始

```powershell
git clone https://github.com/libai3381/claude-desktop-needsremediation-fix.git
cd claude-desktop-needsremediation-fix
.\scripts\diagnose.ps1
```

命中案例时的输出示例（仅为示意，非真实抓取）：

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

| 层级 | 检查项 | 捕获的问题 |
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

## 路线图

- [x] **第一阶段** — README、已知问题文档、只读的 `diagnose.ps1`
- [~] **第二阶段** — 自动修复。`fix-needsremediation.ps1` 已经覆盖了上面这个
  确认过的案例（检测 → 确认 → 验证签名 → 执行）。覆盖 B 级检查项的、更全面的
  分级修复脚本 `fix.ps1` 还没做。
- [ ] **第三阶段** — 社区共建的已知问题数据库，通过 issue 模板结构化提交

本项目刻意先只发布"纯只读"的第一阶段，之后才会碰任何会修改系统状态的功能。
如果你想帮忙一起设计第二阶段的安全边界，欢迎看看 [CONTRIBUTING.md](CONTRIBUTING.md)（英文）。

## 参与贡献

- 遇到了匹配的案例或者新案例？[提交一个已知问题](.github/ISSUE_TEMPLATE/known_issue_submission.yml)。
- 遇到故障需要帮助？[提交诊断报告](.github/ISSUE_TEMPLATE/diagnostic_report.yml)，附上 `diagnose.ps1 -Json` 的输出。
- **发布任何内容前请先脱敏** —— 具体标准见 [CONTRIBUTING.md](CONTRIBUTING.md#before-you-post-anything)（英文）。

## 许可证

[MIT](LICENSE)。商标/从属关系声明见 [DISCLAIMER.md](DISCLAIMER.md)（英文）。
