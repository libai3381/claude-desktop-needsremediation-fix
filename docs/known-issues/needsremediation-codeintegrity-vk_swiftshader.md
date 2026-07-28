# Claude Desktop MSIX: `Modified, NeedsRemediation` after first launch (CodeIntegrity blocks `vk_swiftshader.dll`)

**Status:** Confirmed, reproducible. Root cause traced to Windows Code Integrity
rejecting a bundled DLL in the MSIX package. Workaround confirmed working.
Not yet fixed upstream as of this writing.

**Search terms this covers:** Claude Desktop 打不开 / 修复失败 / 重置失败 /
"Claude needs repair" / "Claude Desktop won't launch after update" / MSIX
`NeedsRemediation` / `0x3CFC` / `0x80073CF6` / `vk_swiftshader.dll` / Code
Integrity Event 3010 / Event 3033.

---

## Summary

Claude Desktop installs successfully as an MSIX package and initially reports
package status `Ok`. The **first time** the app triggers a GPU-accelerated
render path (this reliably includes opening the login/verification page, and
is also triggered by the in-app Browser preview), Windows Code Integrity
blocks the bundled `vk_swiftshader.dll` (SwiftShader, Chromium's software
Vulkan renderer) from loading. The GPU child process dies, Chromium exhausts
its fallback paths and terminates the whole app, and Windows then flags the
**entire MSIX package** as `Modified, NeedsRemediation`. From that point on,
every launch attempt fails, the built-in "Repair" and "Reset" options in
Windows Settings do not fix it, and reinstalling the same MSIX reproduces the
same failure on first launch.

**Confirmed working fix:** reinstall using the official installer's legacy
(non-MSIX) mode:

```powershell
.\ClaudeSetup.exe --exe
```

This installs Claude Desktop as a traditional desktop app instead of an MSIX
package, which avoids the Code Integrity / AppModel path where this bug
lives entirely. It is still the official, signed Anthropic installer and
program — just not packaged as MSIX.

> **`--exe` is an undocumented installer flag.** It worked as of Claude
> Desktop 1.24012.9.0 and is independently confirmed in
> [anthropics/claude-code#81341](https://github.com/anthropics/claude-code/issues/81341),
> but Anthropic could change or remove it in a future installer build without
> notice. **Always verify the installer's digital signature (`Anthropic, PBC`)
> before running it**, regardless of which mode you use — see
> [Verify before you run anything](#verify-before-you-run-anything) below.

---

## Environment this was observed on

- Windows 11 25H2, Build `26200.8655` (also reproduced on `26200.8875` before
  a rollback — see [Windows Update rollback did not help](#windows-update-rollback-did-not-help))
- Claude Desktop `1.24012.9.0`, MSIX package family `Claude_pzs8sxrjxfjjc`
- Reproduced independently across different GPU vendors/configurations
  (multi-GPU laptop/desktop setups, including Intel iGPU + discrete GPU
  combinations per the linked GitHub issues) — this is **not** specific to one
  graphics vendor or one virtual display driver.

This is corroborated by multiple independent reporters on the same Windows
build range; see [Related upstream issues](#related-upstream-issues).

## Symptom timeline

```text
Package installed        → Get-AppxPackage status: Ok
Click Claude icon        → window opens
Login / verification page → shows briefly
Window disappears        → Windows: "This app needs to be repaired"
Get-AppxPackage status   → Modified, NeedsRemediation
"Repair" in Settings     → fails / no effect
"Reset" in Settings      → fails / no effect
Reinstall same MSIX      → status returns to Ok, then fails identically on next launch
```

## Root cause

Two Windows Code Integrity events, captured within the two hours around a
reproduction, tell the whole story:

**Event 3010** (`Microsoft-Windows-CodeIntegrity/Operational`) — Windows
could not load/resolve the package's `AppxMetadata\CodeIntegrity.cat`
catalog file, status `0xC000003A`. The MSIX package does not ship this
catalog (or Windows cannot resolve it), so there is no fallback path for
validating bundled binaries against the package's own integrity catalog.

**Event 3033** (`Microsoft-Windows-CodeIntegrity/Operational`) — Windows
determined that `vk_swiftshader.dll`, loaded by Claude's GPU child process,
does not meet the Microsoft signing-level requirement enforced on that
process (the GPU process runs under a Microsoft-signed-only Code Integrity
Guard policy). The DLL **is** validly Authenticode-signed by "Anthropic, PBC"
— but that is not the signing level Windows requires for this specific
MSIX-packaged, CIG-protected process, and with no `CodeIntegrity.cat` catalog
to fall back to, the load is rejected outright.

The chain from there:

```text
CodeIntegrity.cat missing/unresolvable (Event 3010)
  → vk_swiftshader.dll fails required signing level (Event 3033)
  → GPU child process is killed
  → Chromium exhausts fallback rendering paths, fatally terminates the app
  → Windows flags the package Modified, NeedsRemediation
  → AppModel-Runtime Event 6 logs error 0x3CFC (ERROR_NEEDS_REMEDIATION)
  → every subsequent launch of the package fails at CreateProcess
```

`0x3CFC` (AppModel-Runtime Event 6) is a **consequence** of the package
already being flagged, not the original trigger — don't chase it directly;
the real signal is the Event 3010/3033 pair above.

Critically, **this is not unique to Claude Desktop.** The same
Code-Integrity-vs-bundled-SwiftShader interaction has been reported in
OpenAI's Codex/ChatGPT Electron app
([openai/codex#34133](https://github.com/openai/codex/issues/34133)), which
strongly suggests this is a general MSIX-packaged-Electron/Chromium +
Windows Code Integrity interaction, not an Anthropic-specific defect. Any
Electron app shipping an unsigned-at-the-right-level `vk_swiftshader.dll`
inside an MSIX with CIG enabled on its GPU process is a plausible candidate
for the same failure mode.

## How to check if this is your issue

```powershell
# 1. Package status
Get-AppxPackage -AllUsers -Name Claude | Select-Object Name, Version, Status
# Look for: Modified, NeedsRemediation

# 2. CodeIntegrity events (run right after reproducing the crash)
$since = (Get-Date).AddHours(-2)
Get-WinEvent -FilterHashtable @{
    LogName   = 'Microsoft-Windows-CodeIntegrity/Operational'
    Id        = 3010, 3033
    StartTime = $since
} -ErrorAction SilentlyContinue | Select-Object TimeCreated, Id, Message | Format-List

# 3. AppModel-Runtime confirmation
Get-WinEvent -FilterHashtable @{
    LogName   = 'Microsoft-Windows-AppModel-Runtime/Admin'
    Id        = 6
    StartTime = $since
} -ErrorAction SilentlyContinue | Select-Object TimeCreated, Id, Message | Format-List
```

Or just run [`scripts/diagnose.ps1`](../../scripts/diagnose.ps1) — it runs all
three checks together and tells you directly if this is a match.

## What did *not* fix it

These were tried, in this order, with real evidence for each — useful so you
don't repeat the same dead ends:

| Ruled out | Evidence |
|---|---|
| Fake/tampered installer | `Get-AuthenticodeSignature` on the installer and a freshly-downloaded MSIX both show `Valid`, signed by Anthropic, PBC |
| Corrupted download | Directly downloading the MSIX (bypassing `Setup.exe`) and installing via `Add-AppxPackage` reproduces the identical failure |
| Windows system file corruption | `sfc /scannow` did find and repair unrelated corrupted files; the crash still occurred after the repair, on a clean reboot |
| Broken AppX deployment framework | `AppXSvc`, `ClipSVC`, `StateRepository` all `Running`; `Microsoft.DesktopAppInstaller` status `Ok` |
| Missing WebView2 | WebView2 Evergreen Runtime present, version confirmed via registry; the login page does render before the crash |
| Cowork VM / HCS not initialized | `VirtualMachinePlatform` was indeed disabled and `vmcompute` not running; enabling both and confirming `HCS ready` in logs did not stop the crash |
| Network proxy blocking requests | Proxy (Clash/Mihomo) correctly tunnels HTTPS to `api.anthropic.com`; unrelated `403`/`404`/`405` responses during testing were HTTP-method/endpoint artifacts, not proxy failures |
| `hosts` file tampering | No redirection entries for `claude.ai`, `downloads.claude.ai`, or `api.anthropic.com` |
| Environment variable interference | No `ANTHROPIC_*`/`CLAUDE_*`/`HTTP(S)_PROXY` values that would affect Desktop; a separate Claude Code CLI proxy config exists but is an unrelated tool/process |
| GPU driver / virtual display conflict | Disabling virtual display adapters made no difference; multiple different GPU vendors reproduce the same failure in the linked upstream issues |
| One specific Windows Update (`KB5101650`) | Rolling the build back from `26200.8875` to `26200.8655` did not resolve it — this is not a single-KB regression |

### Windows Update rollback did not help

Given the number of components involved, it's tempting to blame "some
recent Windows update." Rolling back one cumulative update did not change
the outcome, and reinstalling Windows entirely was considered but never
needed — the `--exe` workaround made it unnecessary. If you're tempted to
reinstall Windows over this: don't, try the workaround first.

## What to avoid trying

- **Enabling Developer Mode** (`AllowDevelopmentWithoutDevLicense`) — this is
  a sideloading policy switch, not a Code Integrity fix, and unnecessarily
  widens what your machine will run unsigned.
- **`--disable-gpu-sandbox`** as a long-term flag — reported to work around
  the crash in some cases, but it weakens Chromium's GPU process sandboxing.
  Don't run this persistently.
- **Manually editing `C:\Program Files\WindowsApps`**, replacing
  `vk_swiftshader.dll`, hand-crafting a `CodeIntegrity.cat`, or disabling
  Windows Code Integrity system-wide. Any of these can break package
  signing, Windows Update, or your system's security posture well beyond
  this one app.

## Related upstream issues

These were independently verified to exist and match this root cause:

- [anthropics/claude-code#81745](https://github.com/anthropics/claude-code/issues/81745) — the most detailed writeup; includes the full CIG/signing-level analysis and cross-references the OpenAI Codex report below.
- [anthropics/claude-code#81341](https://github.com/anthropics/claude-code/issues/81341) — independently confirms the `ClaudeSetup.exe --exe` workaround.
- [anthropics/claude-code#80999](https://github.com/anthropics/claude-code/issues/80999) — same root cause triggered by a hidden/off-screen Browser preview pane; notes that **Settings → Apps → Claude → Advanced options → Repair** cleared the `Modified` flag without data loss in that case (worth trying before a full reinstall).
- [anthropics/claude-code#81747](https://github.com/anthropics/claude-code/issues/81747) — same `NeedsRemediation` end state reached via an installer-side `0x80073CF6` failure rather than a post-install crash; useful if your package never reaches `Ok` in the first place.
- [openai/codex#34133](https://github.com/openai/codex/issues/34133) — the same Code-Integrity-vs-bundled-`vk_swiftshader.dll` interaction in OpenAI's Codex/ChatGPT Electron app, supporting the theory that this is a general MSIX+Electron+CIG issue, not Claude-specific.

If Anthropic ships a fix (a signed `vk_swiftshader.dll` at the right signing
level, or a proper `CodeIntegrity.cat` in the package), this document should
be updated to note the fixed version — please open a PR or issue if you
observe that.

## Verify before you run anything

Before running *any* installer from this page or elsewhere:

```powershell
Get-AuthenticodeSignature ".\ClaudeSetup.exe" | Select-Object Status, SignerCertificate
# Expect: Status = Valid, Signer = Anthropic, PBC
```

Only official download sources are: `claude.com/download`,
`claude.ai/download`, and Anthropic's API redirect endpoints under
`api.anthropic.com`. This repository does not host or mirror the installer —
see [DISCLAIMER.md](../../DISCLAIMER.md).

## Contribute your own data point

If you hit this and can add a new Windows build, GPU vendor, or Claude
version to the confirmed-reproduction list, or if `--exe` stops working in a
future version, please open a
[known issue submission](../../.github/ISSUE_TEMPLATE/known_issue_submission.yml).
Scrub personal information first — see [CONTRIBUTING.md](../../CONTRIBUTING.md#before-you-post-anything).
