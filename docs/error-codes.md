# Error code reference

A lookup table for the codes you'll see in `Get-AppxPackage` status, installer
output, and Windows Event Logs while diagnosing Claude Desktop on Windows.
This list only includes codes we have direct evidence for (from this
project's own investigation or a linked, verified upstream issue) — it is
not a generic AppX error dump.

## Package status values

| Status | Meaning |
|---|---|
| `Ok` | Package registered and passing integrity checks. Does not guarantee the app will *run* — see `NeedsRemediation` below, which can follow a clean `Ok` state after first launch. |
| `Modified, NeedsRemediation` | Windows detected a post-registration integrity problem (see Code Integrity events below) and blocked the package from being launched again until repaired or reinstalled. The built-in "Repair"/"Reset" options frequently do **not** clear this — see [the flagship known issue](known-issues/needsremediation-codeintegrity-vk_swiftshader.md). |
| `Staged` | Package deployment did not complete; often paired with `Get-AppxProvisionedPackage -Online` showing an orphaned provisioned copy that re-stages a broken package on next login. |

## HRESULT / NTSTATUS codes

| Code | Where seen | Meaning |
|---|---|---|
| `0x80073CF6` | `AddPackage` failure during install/upgrade | Package could not be registered — classic signature of an MSIX left in a partially-registered ("wedged") state, often from a prior install attempt. See [#81747](https://github.com/anthropics/claude-code/issues/81747), [#49917](https://github.com/anthropics/claude-code/issues/49917). |
| `0x8007007E` | Alongside `0x80073CF6` during re-registration | Module/dependency could not be found or loaded during package registration. |
| `0xC000003A` | Code Integrity Event 3010 | `STATUS_OBJECT_PATH_NOT_FOUND` — Windows could not resolve the package's `AppxMetadata\CodeIntegrity.cat` catalog file. |
| `0xC0000428` / signing-level rejection | Code Integrity Event 3033 | A loaded DLL does not meet the Microsoft signing-level requirement enforced on that process (e.g. `vk_swiftshader.dll` under a Microsoft-signed-only GPU process policy). |
| `0x3CFC` (`ERROR_NEEDS_REMEDIATION`) | AppModel-Runtime Event 6 | `CreateProcess` refused to launch because the package is already flagged `Modified`/`NeedsRemediation`. This is a **downstream symptom**, not the original trigger — check Code Integrity events 3010/3033 instead of chasing this code directly. |
| `0x80073D02` | Install/uninstall attempts | Package files are locked by a running process — kill any hung `Claude.exe` process before retrying. |
| `0x80073CFA` | Uninstall/reinstall sequences | `Remove-AppxPackage` called with an unsupported option combination (e.g. `PreserveApplicationData` on a non-development-mode package) per Microsoft's documented constraints. |

## Where these come from

Event log sources referenced above:

```powershell
# Code Integrity (Events 3010, 3033)
Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational'

# AppModel Runtime (Event 6)
Get-WinEvent -LogName 'Microsoft-Windows-AppModel-Runtime/Admin'

# AppX Deployment (install/uninstall errors, e.g. 0x80073CF6)
Get-WinEvent -LogName 'Microsoft-Windows-AppXDeploymentServer/Operational'
```

`scripts/diagnose.ps1` queries all three and cross-references the result
against this table automatically.

Found a code that's missing here, or seen a different meaning for one of
these in your environment? Open a PR — this table is meant to grow with real
cases, not speculation.
