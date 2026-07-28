# claude-desktop-needsremediation-fix

*[English](README.md) | [简体中文](README.zh-CN.md)*

**Diagnose first. Don't uninstall-and-pray.**
A community toolkit to diagnose and recover Claude Desktop Windows failures
caused by MSIX/AppX, Code Integrity, WebView2, network proxy, and system
compatibility issues.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)
![Windows 10/11](https://img.shields.io/badge/Windows-10%20%2F%2011-0078D6)
![Unofficial](https://img.shields.io/badge/status-unofficial%20%2F%20community-orange)

> **Not an official Anthropic project.** Independent, community-maintained.
> Not affiliated with, endorsed by, or sponsored by Anthropic PBC. "Claude"
> and "Claude Desktop" are Anthropic's trademarks, referenced here only to
> describe compatibility. See [DISCLAIMER.md](DISCLAIMER.md).

## The problem

Claude Desktop breaks in ways generic advice can't fix:

- Won't launch after an update
- Clicking the icon does nothing
- Login page flashes, then the window disappears
- Windows says the app "needs to be repaired" — and repair itself fails

The cause could be MSIX/AppX packaging, Windows Code Integrity, WebView2,
your proxy setup, or (if you use Cowork) Hyper-V/HCS — each can break
independently. "Reinstall, clear cache, reboot" doesn't tell you which one
actually failed.

**The case that started this project:** a fully-reproduced trace of Claude
Desktop's MSIX package silently flipping to `Modified, NeedsRemediation`
after first launch, root-caused to Windows Code Integrity blocking a bundled
DLL, cross-checked against four independently-filed upstream bug reports,
with a confirmed working fix. Read the full writeup:
[docs/known-issues/needsremediation-codeintegrity-vk_swiftshader.md](docs/known-issues/needsremediation-codeintegrity-vk_swiftshader.md).

## Quickstart

```powershell
git clone https://github.com/libai3381/claude-desktop-needsremediation-fix.git
cd claude-desktop-needsremediation-fix
.\scripts\diagnose.ps1
```

Example output when it finds a match (illustrative, not a live capture):

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

It's **read-only** — it inspects package status, Windows Event Logs,
services, and registry values, and never installs, uninstalls, restarts
services, or writes anything.

## What it checks

| Tier | Check | Catches |
|---|---|---|
| A | Claude package status | `Modified`/`NeedsRemediation` state |
| A | Code Integrity Events 3010 / 3033 | Missing `CodeIntegrity.cat`, DLL signing-level rejection |
| A | AppModel-Runtime Event 6 | `0x3CFC` launch blocks caused by the above |
| B | OS version/build/edition | Compatibility (e.g. Cowork needs Pro/Enterprise) |
| B | AppX services (`AppXSvc`, `ClipSVC`, `StateRepository`) | Broken deployment framework |
| B | WebView2 runtime | Missing/outdated runtime |
| B | Proxy (WinINet vs WinHTTP) | Silent install/update failures behind a proxy |
| B | Virtualization / HCS (`vmcompute`) | Cowork-specific VM startup issues |
| B | Hung `Claude.exe` process | Locked-file errors during reinstall |

Full reference: [docs/error-codes.md](docs/error-codes.md) ·
[docs/architecture.md](docs/architecture.md) · [docs/faq.md](docs/faq.md)

## Known confirmed fix (for the NeedsRemediation/CodeIntegrity case)

```powershell
.\ClaudeSetup.exe --exe
```

Installs Claude Desktop in legacy (non-MSIX) mode, bypassing the Code
Integrity/AppModel path where this specific bug lives. This is an
**undocumented installer flag** — verify the installer's signature
(`Anthropic, PBC`) before running it, and see the full writeup for caveats:
[docs/known-issues/needsremediation-codeintegrity-vk_swiftshader.md](docs/known-issues/needsremediation-codeintegrity-vk_swiftshader.md#confirmed-fix).

## Roadmap

- [x] **Phase 1** — README, known-issues docs, read-only `diagnose.ps1`
- [ ] **Phase 2** — tiered auto-fix script (`fix.ps1`), dry-run by default, safe actions only
- [ ] **Phase 3** — community-sourced known-issues database, structured submissions via issue templates

This project deliberately shipped Phase 1 — read-only only — before touching
anything that modifies your system. See [CONTRIBUTING.md](CONTRIBUTING.md) if
you want to help design Phase 2 safely.

## Contributing

- Found a matching or new case? [Submit a known issue](.github/ISSUE_TEMPLATE/known_issue_submission.yml).
- Hit a failure and want help? [File a diagnostic report](.github/ISSUE_TEMPLATE/diagnostic_report.yml) with `diagnose.ps1 -Json` output attached.
- **Scrub personal info before posting anything** — see [CONTRIBUTING.md](CONTRIBUTING.md#before-you-post-anything).

## License

[MIT](LICENSE). See [DISCLAIMER.md](DISCLAIMER.md) for the trademark/affiliation notice.
