<#
.SYNOPSIS
    Cross-vendor decorrelation telemetry -- is the moat still paying for itself?

.DESCRIPTION
    The whole point of two vendors (Claude reviewer != Grok builder) is UNCORRELATED errors. If
    Grok concedes every issue Claude raises, the two have effectively collapsed into one opinion
    (sycophancy / capability convergence) and the second vendor stops earning its cost. This reads
    the latest ledger\REVIEW.json, computes a disagreement rate, appends it to DECORRELATION.jsonl,
    and warns when disagreement drops too low. (AdaptOrch flags "LLM performance convergence" as a
    real 2026 risk; this is the cheap local monitor for it.)

    disagreement = 1 - conceded/raised  (high = healthy independent review; ~0 = converging).

.PARAMETER ReviewFile  REVIEW.json path. Default <repo>\ledger\REVIEW.json.
.PARAMETER WarnBelow   Warn when disagreement drops below this. Default 0.15.
#>
[CmdletBinding()]
param(
    [string]$ReviewFile = "",
    [double]$WarnBelow  = 0.15
)
$ErrorActionPreference = "Continue"
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ReviewFile) { $ReviewFile = Join-Path $repoRoot "ledger\REVIEW.json" }
if (-not (Test-Path $ReviewFile)) { Write-Host "decorrelation: no REVIEW.json yet (run dual-review first)."; exit 0 }

$rev = Get-Content $ReviewFile -Raw | ConvertFrom-Json
$raised   = @($rev.issues).Count
$conceded = @($rev.conceded).Count
$disagreement = if ($raised -gt 0) { [math]::Round(1 - ($conceded / $raised), 3) } else { 0 }

$ledger = Join-Path $repoRoot "ledger"; New-Item -ItemType Directory -Force -Path $ledger | Out-Null
([PSCustomObject]@{ stamp=$rev.stamp; raised=$raised; conceded=$conceded; disagreement=$disagreement } |
    ConvertTo-Json -Compress) | Add-Content -Path (Join-Path $ledger "DECORRELATION.jsonl") -Encoding utf8

Write-Host ("decorrelation: raised={0} conceded={1} disagreement={2}" -f $raised, $conceded, $disagreement)
if ($raised -gt 0 -and $disagreement -lt $WarnBelow) {
    Write-Host "WARN: low cross-vendor disagreement -> vendors converging, moat weakening. Increase prompt/temperature diversity or re-evaluate the second vendor." -ForegroundColor Yellow
}
