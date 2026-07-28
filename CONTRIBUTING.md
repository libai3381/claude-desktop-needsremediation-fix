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
  one, or fix a false positive/negative. Phase 1 is intentionally read-only;
  see the [Roadmap](README.md#roadmap) before proposing anything that changes
  system state.
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

- Keep `scripts/diagnose.ps1` read-only (Phase 1 constraint — no
  `Add-AppxPackage`, no service restarts, no registry writes). Auto-fix
  behavior is Phase 2 and will land as a separate, explicitly-confirmed
  script.
- PowerShell style: prefer built-in cmdlets over external tools, wrap
  environment/log queries that may not exist in `try`/`catch`, and keep checks
  independent (one check failing shouldn't stop the others from running).
- Describe what Windows build / Claude Desktop version you tested against.
