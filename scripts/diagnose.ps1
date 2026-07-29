#Requires -Version 5.1
<#
.SYNOPSIS
    Read-only diagnostic checks for Claude Desktop on Windows.
.DESCRIPTION
    Inspects Claude Desktop's MSIX package status, relevant Windows Event Logs,
    services, and configuration. Makes no changes to the system: no installs,
    no uninstalls, no service restarts, no registry writes.
    See docs/known-issues/needsremediation-codeintegrity-vk_swiftshader.md for
    the flagship case this script's Tier A checks are built around.
.PARAMETER Json
    Emit results as a single JSON object instead of a formatted table. Useful
    for pasting into the diagnostic_report issue template.
.EXAMPLE
    .\diagnose.ps1
.EXAMPLE
    .\diagnose.ps1 -Json | Out-File report.json
#>
[CmdletBinding()]
param(
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param(
        [string]$Tier,
        [string]$Check,
        [ValidateSet('Pass', 'Warn', 'Fail', 'Skip')]
        [string]$Status,
        [string]$Detail,
        [string]$Fix = ''
    )
    $results.Add([PSCustomObject]@{
        Tier   = $Tier
        Check  = $Check
        Status = $Status
        Detail = $Detail
        Fix    = $Fix
    })
}

function Test-IsElevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

$isElevated = Test-IsElevated
Write-Verbose "Running elevated: $isElevated"

# --- Tier A: high-confidence checks from the verified NeedsRemediation/CodeIntegrity case ---

# -AllUsers needs elevation and throws if we don't have it; fall back to the
# current-user-only query so this still works when run unelevated.
$claudePkg = $null
try {
    $claudePkg = Get-AppxPackage -AllUsers -Name 'Claude*' -ErrorAction Stop | Select-Object -First 1
} catch {
    try {
        $claudePkg = Get-AppxPackage -Name 'Claude*' -ErrorAction Stop | Select-Object -First 1
    } catch {
        $claudePkg = $null
    }
}

$packageNeedsRemediation = $false
if (-not $claudePkg) {
    Add-Result -Tier 'A' -Check 'Claude package presence' -Status 'Skip' `
        -Detail 'No package matching "Claude*" found for this user (or all users, if elevated). Claude Desktop may not be installed, or is installed via the legacy non-MSIX (--exe) mode, which this check does not see.'
} else {
    $status = [string]$claudePkg.Status
    if ($status -match 'NeedsRemediation') {
        $packageNeedsRemediation = $true
        Add-Result -Tier 'A' -Check 'Claude package status' -Status 'Fail' `
            -Detail "Status: $status (Version $($claudePkg.Version))" `
            -Fix 'See docs/known-issues/needsremediation-codeintegrity-vk_swiftshader.md'
    } elseif ($status -eq 'Ok') {
        Add-Result -Tier 'A' -Check 'Claude package status' -Status 'Pass' `
            -Detail "Status: Ok (Version $($claudePkg.Version))"
    } else {
        Add-Result -Tier 'A' -Check 'Claude package status' -Status 'Warn' `
            -Detail "Status: $status (Version $($claudePkg.Version))"
    }
}

$since = (Get-Date).AddHours(-2)
$ci3010 = $null
$ci3033 = $null
try {
    $ciEvents = Get-WinEvent -FilterHashtable @{
        LogName   = 'Microsoft-Windows-CodeIntegrity/Operational'
        Id        = 3010, 3033
        StartTime = $since
    } -ErrorAction Stop
    $ci3010 = $ciEvents | Where-Object { $_.Id -eq 3010 } | Select-Object -First 1
    $ci3033 = $ciEvents | Where-Object { $_.Id -eq 3033 } | Select-Object -First 1
} catch [Exception] {
    # Get-WinEvent throws when a query matches zero events - that's the
    # expected, healthy case here (no crash reproduced recently), not a
    # failure. Only surface anything else (e.g. the log itself missing).
    if ($_.Exception -is [System.Diagnostics.Eventing.Reader.EventLogNotFoundException] -or
        $_.CategoryInfo.Category -eq 'ObjectNotFound') {
        # No matching events in the window - not an error, just nothing found.
    } else {
        Write-Verbose "CodeIntegrity event query failed: $($_.Exception.Message)"
    }
}

if ($ci3010) {
    Add-Result -Tier 'A' -Check 'CodeIntegrity Event 3010 (CodeIntegrity.cat)' -Status 'Fail' `
        -Detail "Found within the last 2 hours: $($ci3010.TimeCreated)" `
        -Fix 'Matches the known CodeIntegrity.cat resolution failure. See docs/known-issues/needsremediation-codeintegrity-vk_swiftshader.md'
} else {
    Add-Result -Tier 'A' -Check 'CodeIntegrity Event 3010 (CodeIntegrity.cat)' -Status 'Pass' `
        -Detail 'No matching event in the last 2 hours.'
}

if ($ci3033) {
    $hitsSwiftshader = $ci3033.Message -match 'vk_swiftshader'
    Add-Result -Tier 'A' -Check 'CodeIntegrity Event 3033 (signing level rejected)' -Status 'Fail' `
        -Detail "Found within the last 2 hours: $($ci3033.TimeCreated)$(if ($hitsSwiftshader) { ' - references vk_swiftshader.dll' })" `
        -Fix 'Matches the known signing-level rejection. See docs/known-issues/needsremediation-codeintegrity-vk_swiftshader.md'
} else {
    Add-Result -Tier 'A' -Check 'CodeIntegrity Event 3033 (signing level rejected)' -Status 'Pass' `
        -Detail 'No matching event in the last 2 hours.'
}

$appModelEvent6 = $null
try {
    $appModelEvent6 = Get-WinEvent -FilterHashtable @{
        LogName   = 'Microsoft-Windows-AppModel-Runtime/Admin'
        Id        = 6
        StartTime = $since
    } -ErrorAction Stop | Select-Object -First 1
} catch {
    Write-Verbose "AppModel-Runtime event query returned nothing or failed: $($_.Exception.Message)"
}

if ($appModelEvent6) {
    Add-Result -Tier 'A' -Check 'AppModel-Runtime Event 6 (0x3CFC)' -Status 'Fail' `
        -Detail "Found within the last 2 hours: $($appModelEvent6.TimeCreated)" `
        -Fix 'ERROR_NEEDS_REMEDIATION - a downstream symptom of the package already being flagged. See the CodeIntegrity checks above for the root cause.'
} else {
    Add-Result -Tier 'A' -Check 'AppModel-Runtime Event 6 (0x3CFC)' -Status 'Pass' `
        -Detail 'No matching event in the last 2 hours.'
}

if (-not $isElevated) {
    Add-Result -Tier 'A' -Check 'Event log checks' -Status 'Warn' `
        -Detail 'Not running elevated - CodeIntegrity/AppModel-Runtime event queries may be incomplete. Re-run as Administrator for full results.'
}

# --- Tier B: supporting environmental checks ---

try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).EditionID
    Add-Result -Tier 'B' -Check 'OS version' -Status 'Pass' `
        -Detail "$($os.Caption) Build $($os.BuildNumber), Edition: $edition, Arch: $($os.OSArchitecture)"
} catch {
    Add-Result -Tier 'B' -Check 'OS version' -Status 'Skip' -Detail "Could not query: $($_.Exception.Message)"
}

try {
    $svcNames = 'AppXSvc', 'ClipSVC', 'StateRepository'
    $svcs = Get-Service -Name $svcNames -ErrorAction SilentlyContinue
    $notRunning = $svcs | Where-Object { $_.Status -ne 'Running' }
    if (-not $svcs -or $svcs.Count -lt $svcNames.Count) {
        Add-Result -Tier 'B' -Check 'AppX services' -Status 'Warn' `
            -Detail "Could not find all of: $($svcNames -join ', ')"
    } elseif ($notRunning) {
        Add-Result -Tier 'B' -Check 'AppX services' -Status 'Warn' `
            -Detail "Not running: $(($notRunning | ForEach-Object { $_.Name }) -join ', ')" `
            -Fix 'These services are required for MSIX/AppX apps to install and launch.'
    } else {
        Add-Result -Tier 'B' -Check 'AppX services' -Status 'Pass' -Detail 'AppXSvc, ClipSVC, StateRepository all running.'
    }
} catch {
    Add-Result -Tier 'B' -Check 'AppX services' -Status 'Skip' -Detail "Could not query: $($_.Exception.Message)"
}

try {
    $guid = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    $paths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$guid",
        "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$guid",
        "HKCU:\Software\Microsoft\EdgeUpdate\Clients\$guid"
    )
    $found = $null
    foreach ($p in $paths) {
        $v = Get-ItemProperty -Path $p -Name 'pv' -ErrorAction SilentlyContinue
        if ($v -and $v.pv -and $v.pv -ne '0.0.0.0') { $found = $v.pv; break }
    }
    if ($found) {
        Add-Result -Tier 'B' -Check 'WebView2 runtime' -Status 'Pass' -Detail "Installed, version $found"
    } else {
        Add-Result -Tier 'B' -Check 'WebView2 runtime' -Status 'Warn' `
            -Detail 'Not found in any of the standard EdgeUpdate registry locations.' `
            -Fix 'Install the WebView2 Evergreen Runtime from https://developer.microsoft.com/microsoft-edge/webview2/'
    }
} catch {
    Add-Result -Tier 'B' -Check 'WebView2 runtime' -Status 'Skip' -Detail "Could not query: $($_.Exception.Message)"
}

try {
    $wininet = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    $wininetEnabled = $wininet.ProxyEnable -eq 1
    # netsh has no structured output mode here, so this parses its text
    # output for the literal phrase Windows prints when WinHTTP has no
    # proxy configured.
    $winhttp = (netsh winhttp show proxy) -join ' '
    $winhttpDirect = $winhttp -match 'Direct access'
    if ($wininetEnabled -and $winhttpDirect) {
        Add-Result -Tier 'B' -Check 'Proxy configuration (WinINet vs WinHTTP)' -Status 'Warn' `
            -Detail "WinINet proxy enabled ($($wininet.ProxyServer)) but WinHTTP reports direct access." `
            -Fix 'Installers/updaters use WinHTTP, not your browser proxy. Consider: netsh winhttp import proxy source=ie (run manually, not automated by this script).'
    } elseif ($wininetEnabled) {
        Add-Result -Tier 'B' -Check 'Proxy configuration (WinINet vs WinHTTP)' -Status 'Pass' `
            -Detail "WinINet proxy: $($wininet.ProxyServer). WinHTTP appears configured (not reporting direct access)."
    } else {
        Add-Result -Tier 'B' -Check 'Proxy configuration (WinINet vs WinHTTP)' -Status 'Pass' `
            -Detail 'No user-level (WinINet) proxy configured.'
    }
} catch {
    Add-Result -Tier 'B' -Check 'Proxy configuration (WinINet vs WinHTTP)' -Status 'Skip' -Detail "Could not query: $($_.Exception.Message)"
}

try {
    $vmcompute = Get-Service -Name 'vmcompute' -ErrorAction SilentlyContinue
    $hyperV = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).HypervisorPresent
    if (-not $vmcompute) {
        Add-Result -Tier 'B' -Check 'Virtualization / HCS (Cowork)' -Status 'Skip' `
            -Detail 'vmcompute service not found. Only relevant if you use Cowork; unrelated to base Claude Desktop launch failures.'
    } else {
        Add-Result -Tier 'B' -Check 'Virtualization / HCS (Cowork)' -Status 'Pass' `
            -Detail "vmcompute service: $($vmcompute.Status). HypervisorPresent: $hyperV. Only relevant if you use Cowork."
    }
} catch {
    Add-Result -Tier 'B' -Check 'Virtualization / HCS (Cowork)' -Status 'Skip' -Detail "Could not query: $($_.Exception.Message)"
}

try {
    $proc = Get-Process -Name 'Claude' -ErrorAction SilentlyContinue
    if ($proc) {
        Add-Result -Tier 'B' -Check 'Hung Claude process' -Status 'Warn' `
            -Detail "Claude.exe is currently running (PID $($proc.Id -join ', ')). Installers/reinstalls can fail with locked-file errors (0x80073D02) while it's running." `
            -Fix 'Close Claude Desktop fully (check the system tray) before reinstalling.'
    } else {
        Add-Result -Tier 'B' -Check 'Hung Claude process' -Status 'Pass' -Detail 'No Claude.exe process currently running.'
    }
} catch {
    Add-Result -Tier 'B' -Check 'Hung Claude process' -Status 'Skip' -Detail "Could not query: $($_.Exception.Message)"
}

# --- Verdict ---

$verdict = 'No specific match found. Review the checks above; see docs/faq.md and docs/error-codes.md.'
if ($packageNeedsRemediation -and ($ci3010 -or $ci3033) -and $appModelEvent6) {
    $verdict = 'HIGH CONFIDENCE MATCH: this looks like the CodeIntegrity/vk_swiftshader.dll NeedsRemediation case. ' +
        'Confirmed fix: reinstall using ".\ClaudeSetup.exe --exe" (verify signature first). ' +
        'Details: docs/known-issues/needsremediation-codeintegrity-vk_swiftshader.md'
} elseif ($packageNeedsRemediation) {
    $verdict = 'Package is Modified/NeedsRemediation, but the specific CodeIntegrity 3010/3033 or AppModel event 6 signature was not found in the last 2 hours. ' +
        'Try reproducing the crash, then re-run this script immediately. See docs/known-issues/needsremediation-codeintegrity-vk_swiftshader.md for what to look for.'
}

# --- Output ---

if ($Json) {
    [PSCustomObject]@{
        GeneratedAt = (Get-Date).ToString('o')
        Elevated    = $isElevated
        Verdict     = $verdict
        Results     = $results
    } | ConvertTo-Json -Depth 5
    return
}

Write-Host ''
Write-Host 'Claude Desktop Windows Diagnostic' -ForegroundColor Cyan
Write-Host '==================================' -ForegroundColor Cyan
Write-Host ''

foreach ($tier in 'A', 'B') {
    $tierResults = $results | Where-Object { $_.Tier -eq $tier }
    if (-not $tierResults) { continue }
    $tierLabel = if ($tier -eq 'A') { 'Tier A - NeedsRemediation / CodeIntegrity case' } else { 'Tier B - general environment checks' }
    Write-Host $tierLabel -ForegroundColor DarkCyan
    foreach ($r in $tierResults) {
        $color = switch ($r.Status) {
            'Pass' { 'Green' }
            'Warn' { 'Yellow' }
            'Fail' { 'Red' }
            default { 'Gray' }
        }
        Write-Host ("  [{0,-4}] {1}" -f $r.Status, $r.Check) -ForegroundColor $color
        Write-Host ("         {0}" -f $r.Detail) -ForegroundColor Gray
        if ($r.Fix) {
            Write-Host ("         -> {0}" -f $r.Fix) -ForegroundColor DarkYellow
        }
    }
    Write-Host ''
}

$passCount = ($results | Where-Object { $_.Status -eq 'Pass' }).Count
$warnCount = ($results | Where-Object { $_.Status -eq 'Warn' }).Count
$failCount = ($results | Where-Object { $_.Status -eq 'Fail' }).Count
Write-Host ("Summary: {0} pass, {1} warn, {2} fail" -f $passCount, $warnCount, $failCount)
Write-Host ''
Write-Host 'Verdict:' -ForegroundColor Cyan
Write-Host "  $verdict"
Write-Host ''
Write-Host 'To attach this output to a GitHub issue, re-run with -Json and paste the result.' -ForegroundColor DarkGray
