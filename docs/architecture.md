# Why Claude Desktop breaks on Windows: an explainer

**Read this if:** `diagnose.ps1` didn't match your case to a documented known
issue, and you want to understand which Windows subsystem is likely
involved before digging further. If you already know your symptom matches a
[known issue](known-issues/), skip straight there — this page is background,
not a fix.

Claude Desktop on Windows is distributed exclusively as an **MSIX/AppX**
package (there is no plain `.exe` installer path in the current build, aside
from the undocumented legacy fallback described in the
[flagship known issue](known-issues/needsremediation-codeintegrity-vk_swiftshader.md)).
That packaging choice is what makes failures here different from a typical
"broken .exe" — and why generic advice ("reinstall it") so often fails.

## The layers involved

**MSIX/AppX deployment.** Windows treats the app as a signed, sandboxed
package with its own integrity metadata, not a folder of files you can just
overwrite. `Get-AppxPackage` reports a package *status* (`Ok`, `Modified`,
`NeedsRemediation`, `Staged`, ...) that is tracked independently of whether
the app's files are actually intact. This is why a package can look `Ok`
right after install and still fail — the status can change **after** first
launch, driven by what happens at runtime, not just at install time.

**Windows AppModel.** The layer responsible for actually creating the app's
process (`CreateProcess` for a packaged app goes through AppModel, not a
direct file execution). If AppModel decides a package needs remediation, it
refuses to launch it — regardless of whether the underlying files would
otherwise run fine.

**Windows Code Integrity.** Enforces signing-level requirements on loaded
binaries, especially for hardened child processes like a Chromium GPU
process. A DLL can be validly signed by the vendor (Anthropic, in this case)
and *still* get rejected if it doesn't meet the specific signing level that
process's Code Integrity policy demands, and if the package doesn't ship a
usable integrity catalog (`CodeIntegrity.cat`) as a fallback.

**WebView2.** Claude Desktop's login and much of its UI render through the
Microsoft Edge WebView2 runtime (Evergreen distribution, shared across many
apps). Missing or outdated WebView2 causes a different failure class
entirely — usually a blank window or immediate crash before any UI renders,
rather than the "renders, then dies" pattern seen in the Code Integrity
issue.

**Network / proxy environment.** Two independent Windows proxy stacks exist:
WinINet (browser-level, user-scoped) and WinHTTP (system services, used by
installers and background updaters). They can disagree — proxy configured
for your browser but not for WinHTTP — which produces the specific symptom
of "the app works once open, but installs/updates silently fail."

**Virtualization (Hyper-V / HCS / vmcompute).** Only relevant if you use
Cowork, which runs in a lightweight VM via the Host Compute Service. This
requires Windows Pro/Enterprise/Education (Hyper-V isn't available on Windows
Home), hardware virtualization enabled in firmware, and the
`VirtualMachinePlatform` optional feature turned on. A failure here produces
Cowork-specific errors (`HCS not initialized`, `Failed to load
vmcompute.dll`) and does **not** by itself explain a base Claude Desktop
launch failure — see the flagship known issue for a case where this was
fixed but the actual crash had a different, unrelated cause.

## The core lesson

Because these layers are independent, a single symptom (the app won't
launch) can have causes at completely different layers, and fixing one
layer's real problem (e.g., repairing genuinely corrupted Windows system
files with `sfc /scannow`) doesn't guarantee it was *the* cause of your
specific crash. That's why this project's diagnostic script checks each
layer independently and reports findings per-layer, rather than assuming
a single linear cause.

"Diagnose first" means: collect evidence from each layer, cross-reference
known signatures (see [error-codes.md](error-codes.md)), and only then act —
instead of cycling through generic advice (clear cache, reinstall, reboot,
repeat) hoping something sticks.
