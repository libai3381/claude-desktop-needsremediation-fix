# scripts/

## `diagnose.ps1`

Read-only diagnostic script. Checks Claude Desktop's MSIX package status,
relevant Windows Event Logs (Code Integrity, AppModel Runtime), AppX
services, WebView2, proxy configuration, and virtualization/HCS status.
Makes no changes to your system.

```powershell
# Human-readable table
.\scripts\diagnose.ps1

# Machine-readable output, for pasting into a GitHub issue
.\scripts\diagnose.ps1 -Json

# See Write-Verbose diagnostics for skipped/failed queries
.\scripts\diagnose.ps1 -Verbose
```

Run it elevated (Administrator) for complete results — some checks
(Code Integrity events, all-users package status) return partial data
without elevation, and the script tells you when that happens rather than
failing silently.

No other scripts exist yet. This project intentionally started read-only
only (Phase 1) before adding any automated remediation — see the
[Roadmap](../README.md#roadmap).
