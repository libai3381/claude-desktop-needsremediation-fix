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

## `fix-needsremediation.ps1`

Targeted fix for one specific, confirmed case: the
[NeedsRemediation/CodeIntegrity crash](../docs/known-issues/needsremediation-codeintegrity-vk_swiftshader.md).
This is **not** the general-purpose auto-fix tool described in the
[Roadmap](../README.md#roadmap)'s Phase 2 — it does exactly one thing, for
exactly the one case this project has fully root-caused so far.

```powershell
# Detection only - safe to run any time, changes nothing
.\scripts\fix-needsremediation.ps1

# Detects, and if confirmed, asks before downloading/running anything
.\scripts\fix-needsremediation.ps1 -Apply
```

What it does, in order:

1. **Detect** — reuses `diagnose.ps1`'s Tier A checks and only proceeds if
   the result is `Confidence: high`. Anything less and it stops without
   touching your system.
2. **Confirm** — with `-Apply`, it explains exactly what it's about to do
   and requires you to type `yes` (skip with `-Yes` only if you already
   know what this does).
3. **Fix** — downloads the official installer straight from Anthropic's
   redirect endpoint (`api.anthropic.com`, never a mirror or a bundled
   copy — see [../DISCLAIMER.md](../DISCLAIMER.md)), verifies its
   Authenticode signature is `Valid` and signed by `Anthropic, PBC`
   (**aborts and deletes the file if not**), then runs it with `--exe` to
   install in legacy non-MSIX mode.

It never enables Developer Mode, disables Code Integrity, or bypasses any
MSIX signature check — see the script's own comment-based help
(`Get-Help .\scripts\fix-needsremediation.ps1 -Full`) for the complete
permissions and system-impact breakdown.

No other fix scripts exist yet. A broader, tiered `fix.ps1` covering the
Tier B checks (WebView2, proxy, services, ...) is still future Phase 2 work
— see the [Roadmap](../README.md#roadmap).
