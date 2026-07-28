# Error code reference

**How to use this page:** don't manually pattern-match a code you saw against
this list — run [`scripts/diagnose.ps1`](../scripts/diagnose.ps1) first. It
queries the same package status and event logs referenced below and tells
you directly whether your case matches a documented one. Come back here to
understand what a code actually means, or to look up one `diagnose.ps1`
didn't recognize.

This list only includes codes with direct evidence behind them — from this
project's own investigation, or a linked, verified upstream issue. It is not
a generic AppX error dump.

## Package status values

| Status | Meaning | What to do |
|---|---|---|
| `Ok` | Package registered and passing integrity checks. | Doesn't guarantee the app will *run* — a clean `Ok` can flip to `NeedsRemediation` the first time you launch it. Nothing to do yet; if the app then crashes, re-check status. |
| `Modified, NeedsRemediation` | Windows detected a post-registration integrity problem and blocked the package from launching again until repaired or reinstalled. | Built-in "Repair"/"Reset" frequently do **not** clear this. Check the Code Integrity events below, then see [the flagship known issue](known-issues/needsremediation-codeintegrity-vk_swiftshader.md). |
| `Staged` | Package deployment did not complete. | Check `Get-AppxProvisionedPackage -Online` for an orphaned provisioned copy — it can silently re-stage a broken package on next login. |

## HRESULT / NTSTATUS codes

| Code | Where you'll see it | Meaning | What to do |
|---|---|---|---|
| `0x80073CF6` | `AddPackage` failure during install/upgrade | Package could not be registered — classic signature of an MSIX left in a partially-registered ("wedged") state, often from a prior install attempt. | See [#81747](https://github.com/anthropics/claude-code/issues/81747), [#49917](https://github.com/anthropics/claude-code/issues/49917) for reported cases matching this. |
| `0x8007007E` | Alongside `0x80073CF6` during re-registration | A module/dependency could not be found or loaded during package registration. | Usually accompanies `0x80073CF6` — treat as the same underlying wedged-package problem, not a separate cause. |
| `0xC000003A` | Code Integrity Event 3010 | `STATUS_OBJECT_PATH_NOT_FOUND` — Windows could not resolve the package's `AppxMetadata\CodeIntegrity.cat` catalog file. | Matches the [NeedsRemediation known issue](known-issues/needsremediation-codeintegrity-vk_swiftshader.md) — go there directly. |
| `0xC0000428` / signing-level rejection | Code Integrity Event 3033 | A loaded DLL doesn't meet the Microsoft signing-level requirement enforced on that process (e.g. `vk_swiftshader.dll` under a Microsoft-signed-only GPU process policy). | Same as above — this is the pairing event for `0xC000003A`. |
| `0x3CFC` (`ERROR_NEEDS_REMEDIATION`) | AppModel-Runtime Event 6 | `CreateProcess` refused to launch because the package is already flagged `Modified`/`NeedsRemediation`. | This is a **downstream symptom**, not the original trigger. Don't chase it directly — check Code Integrity events 3010/3033 instead. |
| `0x80073D02` | Install/uninstall attempts | Package files are locked by a running process. | Kill any hung `Claude.exe` process (check the system tray too) before retrying. |
| `0x80073CFA` | Uninstall/reinstall sequences | `Remove-AppxPackage` was called with an unsupported option combination (e.g. `PreserveApplicationData` on a non-development-mode package). | Retry the uninstall without that option combination. |

## Where these logs live

If you want to look at raw events yourself rather than through
`diagnose.ps1`:

```powershell
# Code Integrity (Events 3010, 3033) — unfiltered, can be noisy
Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational'

# AppModel Runtime (Event 6) — unfiltered
Get-WinEvent -LogName 'Microsoft-Windows-AppModel-Runtime/Admin'

# AppX Deployment (install/uninstall errors, e.g. 0x80073CF6) — unfiltered
Get-WinEvent -LogName 'Microsoft-Windows-AppXDeploymentServer/Operational'
```

These commands dump the full log, not just Claude-related entries — for a
targeted query (filtered by ID and time window), see
[the known-issue doc's diagnostic commands](known-issues/needsremediation-codeintegrity-vk_swiftshader.md#how-to-check-if-this-is-your-issue)
or just run `diagnose.ps1`, which does the filtering for you.

Found a code that's missing here, or seen a different meaning for one of
these in your environment? Open a PR — this table is meant to grow with real
cases, not speculation.
