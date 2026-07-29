#Requires -Version 5.1
<#
.SYNOPSIS
    Detects, and (only with explicit confirmation) fixes, the Claude Desktop
    NeedsRemediation/CodeIntegrity MSIX crash documented in
    docs/known-issues/needsremediation-codeintegrity-vk_swiftshader.md.

.DESCRIPTION
    Two phases, always run in this order:

    1. DETECTION (always runs). Calls diagnose.ps1 and reuses its Tier A
       result: Claude package status, CodeIntegrity Events 3010/3033, and
       AppModel-Runtime Event 6. This phase is read-only - see PERMISSIONS
       below - and always runs, even without -Apply.

    2. FIX (only runs if ALL of these are true: detection reported
       Confidence 'high', you passed -Apply, and you confirm interactively -
       or passed -Yes). Downloads the official Claude Desktop installer
       directly from Anthropic's own redirect endpoint, verifies its
       Authenticode signature is Valid and signed by "Anthropic, PBC"
       (aborts otherwise, no exceptions), then runs it with the --exe flag.
       That flag installs Claude Desktop in legacy (non-MSIX) mode, which
       avoids the Code Integrity/AppModel path this bug lives in entirely -
       see the known-issue doc for why this works.

    WHAT THIS SCRIPT WILL NEVER DO, even with -Apply -Yes:
      - Enable Windows Developer Mode / AllowDevelopmentWithoutDevLicense
      - Disable, weaken, or bypass Windows Code Integrity system-wide
      - Use any MSIX signature-check bypass or sideloading policy change
      - Touch any app, service, or registry key other than what the
        official installer itself touches when you run it normally
      - Ship, embed, or reuse a previously-downloaded copy of the
        installer - it is fetched fresh from Anthropic's servers every run
        (see ../DISCLAIMER.md - this repo does not host or mirror it)
      - Suppress or auto-answer the installer's own UAC/consent prompts

    PERMISSIONS AND SYSTEM IMPACT
      Detection phase:
        - No administrator rights required. Some checks (Code Integrity
          event log, all-users package query) return incomplete results
          when run unelevated - same caveat as diagnose.ps1 - but nothing
          in this phase requires it or changes anything.
        - No network access.
      Fix phase (-Apply only):
        - Outbound HTTPS GET to api.anthropic.com (the official installer
          redirect endpoint) to download ClaudeSetup.exe.
        - Writes exactly one file: the downloaded installer, to your
          user Temp folder ($env:TEMP).
        - Runs Get-AuthenticodeSignature (read-only) on that file before
          doing anything else with it.
        - Launches the signed installer with the --exe argument. The
          installer itself will prompt for UAC elevation as it normally
          would - this script does not elevate itself and does not
          suppress that prompt.
        - Does not delete the downloaded installer afterward - it's left
          in Temp so you can independently re-verify it.

.PARAMETER Apply
    Without this switch, the script only detects and reports - it never
    downloads or runs anything. Required (but not sufficient on its own)
    for the fix phase to run.
.PARAMETER Yes
    Skip the interactive "type yes to continue" prompt. Still requires
    -Apply and a Confidence: high detection result. Only use this once you
    already understand exactly what the fix phase does - see .DESCRIPTION.
.EXAMPLE
    .\fix-needsremediation.ps1
    Detection only. Safe to run any time; changes nothing.
.EXAMPLE
    .\fix-needsremediation.ps1 -Apply
    Detects, and if it's a confirmed match, explains exactly what will
    happen and asks you to type "yes" before downloading or running
    anything.
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

# The one and only download source this script will ever use. Hardcoded,
# not user-suppliable, and HTTPS-only - this is the same official redirect
# endpoint documented (and curl-tested) in the known-issue writeup.
$OfficialInstallerUrl = 'https://api.anthropic.com/api/desktop/win32/x64/setup/latest/redirect'
$RequiredSigner = 'Anthropic, PBC'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$diagnosePath = Join-Path $scriptDir 'diagnose.ps1'
$knownIssueDoc = 'docs/known-issues/needsremediation-codeintegrity-vk_swiftshader.md'

Write-Host ''
Write-Host 'Claude Desktop NeedsRemediation Fix' -ForegroundColor Cyan
Write-Host '====================================' -ForegroundColor Cyan
Write-Host ''

# --- Phase 1: detection (always runs, read-only) ---

if (-not (Test-Path $diagnosePath)) {
    Write-Host "Could not find diagnose.ps1 next to this script at: $diagnosePath" -ForegroundColor Red
    exit 1
}

Write-Host 'Running detection (same checks as diagnose.ps1)...' -ForegroundColor DarkCyan
$diagnoseJson = & $diagnosePath -Json
$report = $diagnoseJson | ConvertFrom-Json

$tierAResults = $report.Results | Where-Object { $_.Tier -eq 'A' }
foreach ($r in $tierAResults) {
    $color = switch ($r.Status) {
        'Pass' { 'Green' }
        'Warn' { 'Yellow' }
        'Fail' { 'Red' }
        default { 'Gray' }
    }
    Write-Host ("  [{0,-4}] {1}" -f $r.Status, $r.Check) -ForegroundColor $color
    Write-Host ("         {0}" -f $r.Detail) -ForegroundColor Gray
}

Write-Host ''
Write-Host "Confidence: $($report.Confidence)" -ForegroundColor $(if ($report.Confidence -eq 'high') { 'Green' } else { 'Yellow' })
Write-Host "  $($report.Verdict)"
Write-Host ''

if ($report.Confidence -ne 'high') {
    Write-Host 'This does not look like a confirmed match for the documented NeedsRemediation/CodeIntegrity case.' -ForegroundColor Yellow
    Write-Host "This script will not attempt a fix for an unconfirmed case. See docs/faq.md, or file a" -ForegroundColor Yellow
    Write-Host 'diagnostic report: .github/ISSUE_TEMPLATE/diagnostic_report.yml' -ForegroundColor Yellow
    exit 0
}

Write-Host 'This matches the documented case.' -ForegroundColor Green
Write-Host "Full writeup: $knownIssueDoc"
Write-Host ''

if (-not $Apply) {
    Write-Host 'Detection-only run (no -Apply passed). Nothing was downloaded or changed.' -ForegroundColor DarkGray
    Write-Host 'Re-run with -Apply to proceed to the fix - you will still be asked to confirm.' -ForegroundColor DarkGray
    exit 0
}

# --- Phase 2: fix (only reached with -Apply and Confidence: high) ---

Write-Host 'About to do the following:' -ForegroundColor Cyan
Write-Host "  1. Download the official installer from:`n     $OfficialInstallerUrl"
Write-Host "  2. Verify its digital signature is Valid and signed by `"$RequiredSigner`""
Write-Host '  3. Run it with the --exe flag (installs in legacy, non-MSIX mode)'
Write-Host ''
Write-Host 'This will NOT enable Developer Mode, disable Code Integrity, or bypass any' -ForegroundColor DarkGray
Write-Host 'MSIX signature check. The installer will show its own UAC/consent prompts' -ForegroundColor DarkGray
Write-Host 'as normal - this script does not suppress or auto-answer them.' -ForegroundColor DarkGray
Write-Host ''

if (-not $Yes) {
    $confirmation = Read-Host 'Type "yes" to continue'
    if ($confirmation -ne 'yes') {
        Write-Host 'Aborted - nothing was downloaded or changed.' -ForegroundColor Yellow
        exit 0
    }
}

$installerPath = Join-Path $env:TEMP 'ClaudeSetup-fix.exe'

Write-Host ''
Write-Host "Downloading to $installerPath ..." -ForegroundColor DarkCyan
try {
    # PowerShell 5.1 doesn't always default to TLS 1.2 on older Windows
    # installs; api.anthropic.com requires it. This only adds the flag if
    # it isn't already set - it never weakens whatever's already enabled.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $OfficialInstallerUrl -OutFile $installerPath -UseBasicParsing
} catch {
    Write-Host "Download failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host 'Verifying digital signature...' -ForegroundColor DarkCyan
$sig = Get-AuthenticodeSignature -FilePath $installerPath
$signerOk = $sig.Status -eq 'Valid' -and $sig.SignerCertificate -and
    ($sig.SignerCertificate.Subject -match [regex]::Escape($RequiredSigner))

if (-not $signerOk) {
    Write-Host ''
    Write-Host 'SIGNATURE VERIFICATION FAILED.' -ForegroundColor Red
    Write-Host "  Status: $($sig.Status)"
    Write-Host "  Signer: $(if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { '(none)' })"
    Write-Host "  Expected signer: $RequiredSigner" -ForegroundColor Red
    Write-Host 'Refusing to run this file. Deleting the downloaded copy.' -ForegroundColor Red
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "Signature valid, signed by $RequiredSigner." -ForegroundColor Green
Write-Host ''
Write-Host 'Launching the installer with --exe. Follow any prompts it shows you.' -ForegroundColor Cyan
Write-Host "(File kept at $installerPath if you want to re-verify it yourself.)" -ForegroundColor DarkGray
Write-Host ''

Start-Process -FilePath $installerPath -ArgumentList '--exe' -Wait

Write-Host ''
Write-Host 'Installer finished. Re-checking package status...' -ForegroundColor DarkCyan
$recheckJson = & $diagnosePath -Json
$recheck = $recheckJson | ConvertFrom-Json
$pkgCheck = $recheck.Results | Where-Object { $_.Check -eq 'Claude package status' -or $_.Check -eq 'Claude package presence' } | Select-Object -First 1

if ($pkgCheck) {
    Write-Host ("  [{0}] {1}" -f $pkgCheck.Status, $pkgCheck.Detail)
}
Write-Host ''
Write-Host 'If Claude Desktop now launches normally, you are done - no further action needed.' -ForegroundColor Green
Write-Host 'If it still fails, please file a diagnostic report: .github/ISSUE_TEMPLATE/diagnostic_report.yml' -ForegroundColor DarkGray
