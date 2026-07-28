# FAQ

**Is this an official Anthropic project?**
No. See [DISCLAIMER.md](../DISCLAIMER.md). It's community-maintained, started
from one user's own troubleshooting case.

**Does `diagnose.ps1` change anything on my system?**
No. Phase 1 (the current state of this project) is strictly read-only — it
only inspects package status, Windows Event Logs, services, and registry
values. It never installs, uninstalls, restarts services, or writes
anything. See the [Roadmap](../README.md#roadmap) for what a future,
explicitly-confirmed auto-fix script might add.

**Do I need to run it as Administrator?**
No, but some checks (Code Integrity events, `Get-AppxPackage -AllUsers`,
`Get-AppxProvisionedPackage`) need elevation to return complete data. Running
unelevated still works — those specific checks will report that they were
skipped and why.

**My package shows `Modified, NeedsRemediation` but the Code Integrity
events don't mention `vk_swiftshader.dll` — is this the same bug?**
Not necessarily. `NeedsRemediation` is a general package state, not unique to
this one root cause. Check what `diagnose.ps1` reports for Events 3010/3033 —
if they point at a different DLL or aren't present at all, you're likely
hitting a different issue. Please still file a
[diagnostic report](../.github/ISSUE_TEMPLATE/diagnostic_report.yml) so it
can be tracked as a separate case.

**Will `ClaudeSetup.exe --exe` always work?**
It worked as of Claude Desktop `1.24012.9.0`. It's an undocumented flag, not
a supported API — Anthropic could change or remove it at any time. Always
verify the installer's signature first (see the
[flagship known issue](known-issues/needsremediation-codeintegrity-vk_swiftshader.md#verify-before-you-run-anything)).
If it stops working, please open an issue so this doc can be updated.

**Why not just tell people to reinstall Windows / disable Code Integrity /
enable Developer Mode?**
Because none of those are proportionate to the actual problem, and some
(disabling Code Integrity, broad Developer Mode sideloading) meaningfully
reduce your system's security for a single app's bug. See
[What to avoid trying](known-issues/needsremediation-codeintegrity-vk_swiftshader.md#what-to-avoid-trying).

**Can I use this for other Electron/MSIX apps with similar symptoms?**
The Code Integrity + bundled `vk_swiftshader.dll` failure mode is not
Claude-specific — see the cross-reference to
[openai/codex#34133](https://github.com/openai/codex/issues/34133) in the
known issue doc. The general checks in `diagnose.ps1` (package status, Code
Integrity events, WebView2, proxy) are useful for diagnosing any
MSIX-packaged Windows app, though the tool's output and known-issue links are
currently written with Claude Desktop specifically in mind.

**How do I contribute a new known-issue case?**
See [CONTRIBUTING.md](../CONTRIBUTING.md) — scrub personal data first, then
use the
[known issue submission](../.github/ISSUE_TEMPLATE/known_issue_submission.yml)
template.
