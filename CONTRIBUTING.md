# Contributing

Thanks for helping make Claude Desktop on Windows less painful to debug. This
project grows through real diagnostic reports and known-issue writeups, not
just code.

## Ways to contribute

- **Report a diagnostic case** — run `scripts/diagnose.ps1 -Json`, then open a
  [Diagnostic report](.github/ISSUE_TEMPLATE/diagnostic_report.yml) issue and
  paste the output.
- **Submit a known issue** — if you found a root cause and a fix (even a
  workaround), open a
  [Known issue submission](.github/ISSUE_TEMPLATE/known_issue_submission.yml).
  Well-documented cases get folded into `docs/known-issues/`.
- **Improve `diagnose.ps1`** — add a new read-only check, improve an existing
  one, or fix a false positive/negative. It stays read-only; see
  [Pull requests](#pull-requests) below before proposing anything that
  changes system state.
- **Improve `fix-needsremediation.ps1`** — the one fix script that exists so
  far, scoped to the one case this project has fully root-caused. See
  [scripts/README.md](scripts/README.md#fix-needsremediationps1) for what it
  does and the constraints it follows.
- **Improve the docs** — `docs/error-codes.md` and `docs/architecture.md` are
  living references. Corrections and additions welcome.

## Before you post anything

Scrub the following from logs, screenshots, and diagnostic output before
sharing:

- Windows username, full file paths containing it, or device name
- Email address or Claude account identifiers
- `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, or any other token
- Third-party proxy/API URLs or subscription links
- Cookies, session tokens, or browser storage dumps
- The installer or MSIX file itself (link to the official download instead —
  see [DISCLAIMER.md](DISCLAIMER.md))

`scripts/diagnose.ps1` does not collect any of the above by design, but always
review output before pasting it into a public issue.

## Pull requests

- Keep `scripts/diagnose.ps1` read-only — no `Add-AppxPackage`, no service
  restarts, no registry writes.
- New fix scripts follow `fix-needsremediation.ps1`'s pattern: detect first
  and refuse to proceed on anything less than a confirmed match, explain
  exactly what will happen before doing it, require explicit confirmation
  (`-Apply` + interactive "yes", or an equivalent), and never use Developer
  Mode, disable Code Integrity, or bypass an MSIX signature check as a
  shortcut. If a fix can't be done safely within those constraints, it
  should print instructions for the user to run manually instead of
  automating it.
- PowerShell style: prefer built-in cmdlets over external tools, wrap
  environment/log queries that may not exist in `try`/`catch`, and keep checks
  independent (one check failing shouldn't stop the others from running).
- Describe what Windows build / Claude Desktop version you tested against.
