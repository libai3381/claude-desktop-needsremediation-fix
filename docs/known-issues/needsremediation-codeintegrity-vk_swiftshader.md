# Claude Desktop MSIX: `Modified, NeedsRemediation` after first launch (CodeIntegrity blocks `vk_swiftshader.dll`)

**Status:** Confirmed, reproducible. Not yet fixed upstream as of this writing.

**Search terms this covers:** Claude Desktop 打不开 / 修复失败 / 重置失败 /
"Claude needs repair" / "Claude Desktop won't launch after update" / MSIX
`NeedsRemediation` / `0x3CFC` / `0x80073CF6` / `vk_swiftshader.dll` / Code
Integrity Event 3010 / Event 3033.

---

## Root cause

Claude Desktop's MSIX package ships `vk_swiftshader.dll` (SwiftShader,
Chromium's software Vulkan renderer) without a usable
`AppxMetadata\CodeIntegrity.cat` catalog. The first time the app renders a
GPU-accelerated page — the login/verification screen, or the in-app Browser
preview — Windows Code Integrity has no catalog to validate that DLL against,
rejects it outright, and kills the GPU process. Chromium then fatally
terminates the whole app, and Windows permanently flags the package
`Modified, NeedsRemediation`. A confirmed fix exists that avoids this path
entirely — see [Confirmed fix](#confirmed-fix).

The log evidence, from `Microsoft-Windows-CodeIntegrity/Operational`,
captured immediately after reproducing the crash:

**Event 3010** — Windows could not load/resolve
`AppxMetadata\CodeIntegrity.cat`, status `0xC000003A`. Without this catalog
there is no fallback path for validating the package's bundled binaries.

**Event 3033** — Windows determined that `vk_swiftshader.dll`, loaded by
Claude's GPU child process, does not meet the Microsoft signing-level
requirement enforced on that process (the GPU process runs under a
Microsoft-signed-only Code Integrity Guard policy). The DLL **is** validly
Authenticode-signed by "Anthropic, PBC" — but that's not the signing level
this specific MSIX-packaged, CIG-protected process requires, and with no
`CodeIntegrity.cat` to fall back to, the load is rejected outright.

Put together, the full causal chain:

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

**This is not unique to Claude Desktop.** The same
Code-Integrity-vs-bundled-SwiftShader interaction has been reported in
OpenAI's Codex/ChatGPT Electron app
([openai/codex#34133](https://github.com/openai/codex/issues/34133)), which
strongly suggests this is a general MSIX-packaged-Electron/Chromium +
Windows Code Integrity interaction, not an Anthropic-specific defect. Any
Electron app shipping an unsigned-at-the-right-level `vk_swiftshader.dll`
inside an MSIX with CIG enabled on its GPU process is a plausible candidate
for the same failure mode.

---

## Environment this was observed on

- Windows 11 25H2, Build `26200.8655` (also reproduced on `26200.8875`)
- Claude Desktop `1.24012.9.0`, MSIX package family `Claude_pzs8sxrjxfjjc`
- Reproduced across multiple GPU vendors and multi-GPU laptop/desktop setups
  (see the linked GitHub issues below) — **not** specific to one graphics
  vendor or virtual display driver

Corroborated by multiple independent reporters on the same Windows build
range — see [Related upstream issues](#related-upstream-issues).

## What you'll see

### At startup

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

### While troubleshooting

If you go looking for the cause yourself before finding this page, here's
what you'll likely run into — in the order it happened during the original
investigation:

| Suspected cause | What was tried | What happened |
|---|---|---|
| Tampered/fake installer | `Get-AuthenticodeSignature` on the installer and a freshly-downloaded MSIX | Both `Valid`, signed by `Anthropic, PBC` — not this |
| Corrupted download | Downloaded the MSIX directly (bypassing `Setup.exe`), installed via `Add-AppxPackage` | Same crash on first launch — the installer/bootstrapper isn't the problem either |
| Windows system file corruption | `DISM /Online /Cleanup-Image /RestoreHealth`, then `sfc /scannow` | Real corruption found and repaired; crash still occurred after a clean reboot — a genuine issue, but not this one |
| Broken AppX/MSIX deployment framework | Checked `AppXSvc`, `ClipSVC`, `StateRepository`, `Microsoft.DesktopAppInstaller` | All healthy / `Ok` |
| Missing WebView2 | Checked Evergreen Runtime version in registry; watched the login page actually render | Present and working — the page renders before the crash, so WebView2 isn't the blocker |
| Cowork VM/HCS not initialized | Enabled `VirtualMachinePlatform`, started `vmcompute` (logs had shown `HCS not initialized`) | Fixed a real problem (`HCS ready` confirmed in logs) — but the crash still happened afterward |
| Network proxy blocking requests | Traced the Clash/Mihomo tunnel to `api.anthropic.com` end to end | Proxy working correctly; the `403`/`404`/`405` seen during testing were HTTP-method/endpoint artifacts, not proxy failures |
| `hosts` file / environment variable tampering | Checked for Anthropic-domain redirects and `ANTHROPIC_*`/`CLAUDE_*`/proxy env vars | Clean |
| GPU driver / virtual display conflict | Disabled virtual display adapters; compared across GPU vendors | No change — and the same crash reproduces across different GPU vendors in the linked upstream issues |
| One specific Windows Update | Rolled the build back from `26200.8875` to `26200.8655` | Crash persisted — not a single-KB regression |
| **Code Integrity event logs** | Reproduced the crash, then immediately queried `Microsoft-Windows-CodeIntegrity/Operational` for the surrounding two hours | **This is what actually explained it** — see [Root cause](#root-cause) above |

None of the individual fixes above were wasted effort — several fixed real,
separate problems (system file corruption, HCS/VM setup) — they just weren't
*this* problem.

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

## Confirmed fix

```powershell
.\ClaudeSetup.exe --exe
```

Reinstall using the official installer's legacy (non-MSIX) mode. This
installs Claude Desktop as a traditional desktop app instead of an MSIX
package, avoiding the Code Integrity/AppModel path where this bug lives
entirely. It's still the official, signed Anthropic installer and program —
just not packaged as MSIX.

> **`--exe` is an undocumented installer flag.** It worked as of Claude
> Desktop 1.24012.9.0 and is independently confirmed in
> [anthropics/claude-code#81341](https://github.com/anthropics/claude-code/issues/81341),
> but Anthropic could change or remove it in a future installer build without
> notice.

Before running it — or any installer from this page or elsewhere — verify
the signature:

```powershell
Get-AuthenticodeSignature ".\ClaudeSetup.exe" | Select-Object Status, SignerCertificate
# Expect: Status = Valid, Signer = Anthropic, PBC
```

Only official download sources: `claude.com/download`, `claude.ai/download`,
and Anthropic's API redirect endpoints under `api.anthropic.com`. This
repository does not host or mirror the installer — see
[DISCLAIMER.md](../../DISCLAIMER.md).

## What to avoid trying

- **Reinstalling Windows.** It's tempting once you've ruled out this many
  components, but it was never necessary here — try the `--exe` workaround
  first.
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

## Contribute your own data point

If you hit this and can add a new Windows build, GPU vendor, or Claude
version to the confirmed-reproduction list, or if `--exe` stops working in a
future version, please open a
[known issue submission](../../.github/ISSUE_TEMPLATE/known_issue_submission.yml).
Scrub personal information first — see [CONTRIBUTING.md](../../CONTRIBUTING.md#before-you-post-anything).
