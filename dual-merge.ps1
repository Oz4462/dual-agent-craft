<#
.SYNOPSIS
    No-Cut Merge-Gate: fuehrt einen Branch nur dann in main, wenn (a) die Akzeptanz-
    kriterien gruen sind und (b) kein git-Konflikt entsteht. Bei Konflikt: Abbruch,
    nie automatisches Ueberschreiben.

.DESCRIPTION
    Erzwingt Protokoll-Invarianten 3+4: kein stilles Ueberschreiben, kein falsches "fertig".
    Verify laeuft im Kandidaten-Branch (eigener temp-worktree, stoert den Checkout nicht).

.PARAMETER From    Quell-Branch (Default feat/harden)
.PARAMETER Into    Ziel-Branch (Default main)
.PARAMETER Verify  Test-/Build-Befehl, der gruen sein muss (z.B. "pytest -q").
.PARAMETER Force   Merge ohne Verify erlauben (nicht empfohlen).

.EXAMPLE
    .\dual-merge.ps1 -From feat/harden -Verify "pytest -q"
#>
[CmdletBinding()]
param(
    [string]$From   = "feat/harden",
    [string]$Into   = "main",
    [string]$Verify = "",
    [switch]$Force
)
$ErrorActionPreference = "Continue"  # PS 5.1: unter "Stop" terminiert nativer git-stderr faelschlich
function Fail($m){ Write-Host "BLOCKED: $m" -ForegroundColor Red; exit 1 }
function Ok($m){ Write-Host $m -ForegroundColor Green }
# PS 5.1: native git schreibt nach stderr -> $? wird unzuverlaessig. Immer $LASTEXITCODE pruefen.
function GitFails($m){ if ($LASTEXITCODE -ne 0) { Fail $m } }

# --- Preconditions ---------------------------------------------------------
git rev-parse --is-inside-work-tree 2>$null | Out-Null; GitFails "Kein git-Repo."
git rev-parse --verify $From 2>$null | Out-Null; GitFails "Branch fehlt: $From"
git rev-parse --verify $Into 2>$null | Out-Null; GitFails "Branch fehlt: $Into"
if (git status --porcelain) { Fail "Working tree nicht clean - erst committen/stashen." }

# --- Ownership / Overlap-Report (Transparenz vor dem Merge) ----------------
$base = (git merge-base $Into $From).Trim()
$fromFiles = git diff --name-only $base $From
$intoFiles = git diff --name-only $base $Into
$overlap = $fromFiles | Where-Object { $intoFiles -contains $_ }

Write-Host "=== No-Cut Merge-Gate ===" -ForegroundColor Cyan
Write-Host "From: $From  Into: $Into  Base: $base"
Write-Host "Dateien geaendert in ${From}: $($fromFiles.Count)"
if ($overlap) {
    Write-Host "WARNUNG - beide Seiten haben dieselben Dateien angefasst:" -ForegroundColor Yellow
    $overlap | ForEach-Object { Write-Host "  ! $_" -ForegroundColor Yellow }
    Write-Host "  (git-Merge entscheidet je Zeile; echte Konflikte brechen ab.)"
} else {
    Ok "Kein Datei-Overlap zwischen $From und $Into - kollisionsfrei."
}

# --- Verify-Gate (im temp-worktree des Kandidaten) -------------------------
if ($Verify) {
    $tmp = Join-Path $env:TEMP ("dualgate-" + (Get-Date -Format "HHmmss"))
    git worktree add --detach $tmp $From 2>$null | Out-Null; GitFails "worktree add fehlgeschlagen."
    Push-Location $tmp
    Write-Host "`nVerify im Kandidaten: $Verify"
    $verifyOk = $true
    try { Invoke-Expression $Verify; if ($LASTEXITCODE -ne 0) { $verifyOk = $false } }
    catch { $verifyOk = $false; Write-Host $_.Exception.Message -ForegroundColor Red }
    Pop-Location
    git worktree remove --force $tmp *> $null
    if (-not $verifyOk) { Fail "Verify ROT - kein Merge (Invariante 4)." }
    Ok "Verify GRUEN."
} elseif (-not $Force) {
    Fail "Kein -Verify angegeben. Mit -Force ueberstimmen (nicht empfohlen)."
} else {
    Write-Host "Verify uebersprungen (-Force)." -ForegroundColor Yellow
}

# --- Merge (Konflikt = Abbruch, nie ueberschreiben) ------------------------
git checkout $Into 2>$null | Out-Null
git merge --no-ff --no-edit $From
if ($LASTEXITCODE -ne 0) {
    git merge --abort
    Fail "git-Konflikt - Merge abgebrochen. Mensch entscheidet (Invariante 3)."
}
Ok "`nMERGED: $From -> $Into. No-Cut eingehalten."
git log --oneline -1
