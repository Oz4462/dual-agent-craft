<#
.SYNOPSIS
    Headless-spend budget guard -- fail BLOCKED before the credit pool is exhausted.

.DESCRIPTION
    Sums this month's metered Claude spend from ledger\SPEND.jsonl (written by claude-call.ps1)
    and refuses to proceed if spent + estimate would exceed CapUsd * SafetyPct. This converts the
    "requests silently STOP mid-merge" failure into a clean, early BLOCKED (rule 50). Refuses only;
    it never weakens a call, so it is quality-neutral by construction.

.PARAMETER CapUsd     Monthly budget ceiling in USD. Default 100 (Max 5x headless pool).
.PARAMETER SafetyPct  Fraction of the cap allowed before blocking. Default 0.9.
.PARAMETER Estimate   Estimated USD cost of the call you are about to make. Default 0.
.PARAMETER SpendFile  SPEND.jsonl path. Default <repo>\ledger\SPEND.jsonl.

.OUTPUTS exit 0 = within budget, exit 2 = BLOCKED. Prints a summary line.
#>
[CmdletBinding()]
param(
    [double]$CapUsd    = 100,
    [double]$SafetyPct = 0.9,
    [double]$Estimate  = 0,
    [string]$SpendFile = ""
)
$ErrorActionPreference = "Continue"
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $SpendFile) { $SpendFile = Join-Path $repoRoot "ledger\SPEND.jsonl" }

$month = Get-Date -Format "yyyyMM"
$spent = 0.0
if (Test-Path $SpendFile) {
    Get-Content $SpendFile | ForEach-Object {
        if (-not "$_".Trim()) { return }
        try {
            $e = $_ | ConvertFrom-Json
            if ("$($e.stamp)".StartsWith($month) -and $null -ne $e.cost_usd) { $spent += [double]$e.cost_usd }
        } catch { }
    }
}
$limit  = $CapUsd * $SafetyPct
$wouldBe = $spent + $Estimate
$ok = ($wouldBe -le $limit)

$col = if ($ok) { "Green" } else { "Red" }
Write-Host ("budget-guard [{0}]: spent={1:N2} + est={2:N2} = {3:N2} USD  vs limit={4:N2} (cap={5} x {6}) -> {7}" -f `
    $month, $spent, $Estimate, $wouldBe, $limit, $CapUsd, $SafetyPct, $(if ($ok) { "OK" } else { "BLOCKED" })) -ForegroundColor $col
if (-not $ok) {
    Write-Host ("BLOCKED: would exceed budget by {0:N2} USD. Raise -CapUsd or wait for the monthly reset." -f ($wouldBe - $limit)) -ForegroundColor Red
    exit 2
}
exit 0
