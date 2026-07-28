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
render path — reliably including the login/verification page, also triggered
by the in-app Browser preview — the package crashes and Windows flags it
`Modified, NeedsRemediation`. From that point on every launch fails, and the
built-in "Repair"/"Reset" options don't fix it.

This document walks through the elimination process that led to the actual
cause (see [Investigation](#investigation) and [Root cause](#root-cause)) and
a fix confirmed to work (see [Confirmed fix](#confirmed-fix)).

---

## Environment this was observed on

- Windows 11 25H2, Build `26200.8655` (also reproduced on `26200.8875` —
  rolling back the update didn't change the outcome, see
  [Investigation](#investigation) step 10)
- Claude Desktop `1.24012.9.0`, MSIX package family `Claude_pzs8sxrjxfjjc`
- Reproduced across multiple GPU vendors and multi-GPU laptop/desktop setups
  (see the linked GitHub issues below) — **not** specific to one graphics
  vendor or virtual display driver

Corroborated by multiple independent reporters on the same Windows build
range — see [Related upstream issues](#related-upstream-issues).

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

## Investigation

A signed, cleanly-installed package crashing the same way on first render is
not explained by any of the usual advice. Each plausible cause was tested in
turn, in the order below, until the logs pointed at the real one.

1. **Tampered or fake installer?** `Get-AuthenticodeSignature` on both the
   installer and a freshly-downloaded MSIX returned `Valid`, signed by
   `Anthropic, PBC`. **Ruled out.**

2. **Corrupted download?** Downloaded the MSIX directly (bypassing
   `Setup.exe`) and installed it with `Add-AppxPackage` — same crash on first
   launch. **Ruled out**, and this also clears the installer/bootstrapper
   itself: a manually verified, directly-installed package fails identically.

3. **Windows system file corruption?** `DISM /Online /Cleanup-Image
   /RestoreHealth` and `sfc /scannow` both found and repaired real
   corruption. After a clean reboot, the crash still occurred. A genuine
   problem — just not this one.

4. **Broken AppX/MSIX deployment framework?** `AppXSvc`, `ClipSVC`, and
   `StateRepository` all `Running`; `Microsoft.DesktopAppInstaller` reported
   `Ok`. **Ruled out.**

5. **Missing WebView2?** Evergreen Runtime present, version confirmed via
   registry — and the login page does render before the crash, which is
   itself evidence WebView2 isn't the blocker. **Ruled out.**

6. **Cowork VM/HCS not initialized?** Logs showed `Failed to load
   vmcompute.dll` / `HCS not initialized`, and `VirtualMachinePlatform` was
   indeed disabled. Enabling it and starting `vmcompute` fixed *that*
   problem (`HCS ready` confirmed in logs) — but the crash still happened
   afterward. Real issue, not the cause of this one.

7. **Network/proxy blocking requests?** Traced the Clash/Mihomo proxy
   tunneling to `api.anthropic.com` end to end; the `403`/`404`/`405`
   responses seen during testing turned out to be HTTP-method/endpoint
   artifacts of the test requests themselves, not proxy failures.
   **Ruled out.**

8. **`hosts` file or environment variable tampering?** No redirection
   entries for any Anthropic domain, and no `ANTHROPIC_*`/`CLAUDE_*`/proxy
   environment variables affecting Desktop specifically. **Ruled out.**

9. **GPU driver or virtual display conflict?** Disabling virtual display
   adapters made no difference, and the same crash reproduces across
   different GPU vendors in the linked upstream issues. **Ruled out** as
   vendor- or driver-specific.

10. **One specific Windows Update?** Rolled the build back from
    `26200.8875` to `26200.8655` — crash persisted. Not a single-KB
    regression.

None of that explains a signed, uncorrupted package failing the same way
every time on first GPU render. The next step wasn't another component to
poke at — it was pulling the Windows Event Logs generated at the exact
moment of the crash:

11. **Code Integrity logs.** Reproduced the crash, then immediately queried
    `Microsoft-Windows-CodeIntegrity/Operational` for the surrounding two
    hours. This is where the actual cause showed up — see
    [Root cause](#root-cause) below.

## Root cause

Two events from that query explain everything the investigation above
couldn't:

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
