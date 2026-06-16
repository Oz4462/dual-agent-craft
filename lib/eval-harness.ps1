<#
.SYNOPSIS
    Graded acceptance scorer for the dual-agent merge gate (pass@k / pass^k).

.DESCRIPTION
    Runs a verify command K times and reports two metrics, grounded in the
    literature surfaced by the design study:
      - pass@k  : at least 1 of K runs passed -> the build CAN solve it (exploration).
      - pass^k  : ALL K runs passed           -> it solves it RELIABLY (the merge gate).
    tau-bench (Yao et al. 2024) showed pass@1 is wildly over-optimistic for agents
    (GPT-4o 61% pass@1 vs ~25% pass@8), so the honest merge criterion is pass^k == 1,
    i.e. "green once" is NOT "done". This scorer is the objective referee that decides
    merges and breaks debate ties, so neither agent can win by rhetoric.

    Writes EVAL.json (UTF-8) and returns the result object.

.PARAMETER Verify    The command whose exit code 0 means "pass" (e.g. "pytest -q").
.PARAMETER K         Repetitions. Default 5.
.PARAMETER Cwd       Directory to run the verify in. Default: current.
.PARAMETER Threshold Min pass-rate for score_ok. Default 1.0 (== pass^k, the strict gate).
.PARAMETER OutFile   Where to write the JSON. Default: <repo>\ledger\EVAL.json.

.EXAMPLE
    & .\lib\eval-harness.ps1 -Verify "pytest -q" -K 5 -Cwd $wt
    # merge only if (Get-Content ledger\EVAL.json | ConvertFrom-Json).pass_pow_k -eq 1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Verify,
    [int]   $K         = 5,
    [string]$Cwd       = (Get-Location).Path,
    [double]$Threshold = 1.0,
    [string]$OutFile   = ""
)
$ErrorActionPreference = "Continue"  # PS 5.1: native stderr must not terminate.
if ($K -lt 1) { $K = 1 }

$runs   = New-Object System.Collections.ArrayList
$passes = 0
$earlyStopped = $false
for ($i = 1; $i -le $K; $i++) {
    Push-Location $Cwd
    $code = $null
    try { Invoke-Expression $Verify *> $null; $code = $LASTEXITCODE }
    catch { $code = 1 }
    Pop-Location
    if ($null -eq $code) { $code = 0 }   # pure cmdlet, no native exit, no throw -> pass
    $ok = ($code -eq 0)
    if ($ok) { $passes++ }
    [void]$runs.Add([PSCustomObject]@{ run = $i; exit = $code; pass = $ok })
    # Early-stop (mathematically LOSSLESS): under the strict pass^k gate (Threshold>=1) a single
    # red already forces pass_pow_k=0 -- no remaining run can change the verdict. Saves up to
    # (K-1)/K verify runs on every failing build; the merge decision is bit-identical.
    if (-not $ok -and $Threshold -ge 1.0) { $earlyStopped = $true; break }
}

$rate      = [math]::Round($passes / $K, 4)
$passAtK   = [int]($passes -ge 1)
$passPowK  = [int]($passes -eq $K)
$scoreOk   = ($rate -ge $Threshold)

$result = [PSCustomObject]@{
    verify     = $Verify
    k          = $K
    passes     = $passes
    rate       = $rate
    pass_at_k  = $passAtK
    pass_pow_k = $passPowK
    threshold  = $Threshold
    score_ok   = $scoreOk
    runs          = $runs
    runs_executed = $runs.Count
    early_stopped = $earlyStopped
    stamp      = (Get-Date -Format "o")
}

if (-not $OutFile) {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $ledger   = Join-Path $repoRoot "ledger"
    New-Item -ItemType Directory -Force -Path $ledger | Out-Null
    $OutFile  = Join-Path $ledger "EVAL.json"
}
$result | ConvertTo-Json -Depth 6 | Set-Content -Path $OutFile -Encoding utf8

$col = if ($passPowK -eq 1) { "Green" } elseif ($passAtK -eq 1) { "Yellow" } else { "Red" }
Write-Host ("eval: {0}/{1} passed  rate={2}  pass@k={3}  pass^k={4}  score_ok={5}" -f `
    $passes, $K, $rate, $passAtK, $passPowK, $scoreOk) -ForegroundColor $col
$result
