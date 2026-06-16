<#
.SYNOPSIS
    Dual-Agent CRAFT loop, Render-Phase: laesst Grok einen POC gegen PLAN.md bauen.

.DESCRIPTION
    Claude schreibt PLAN.md (Contract). Dieses Script ruft Grok Build headless in
    einem isolierten git-worktree und laesst N Varianten parallel bauen (--best-of-n).
    Danach reviewt/haertet Claude den worktree-Branch (Schritt A+F des CRAFT-Loops).

    Laeuft auf dem Grok-Abo (OAuth), KEIN xAI-API-Key noetig.
    Merged NICHT automatisch - Review bleibt bei Claude/dir.

.PARAMETER Plan
    Pfad zur Contract-Datei. Default: .\PLAN.md

.PARAMETER Variants
    Anzahl paralleler POC-Varianten (Grok --best-of-n). Default: 3

.PARAMETER Branch
    Name des worktree-Branches, in dem Grok baut. Default: feat/poc

.PARAMETER Model
    Optionales Grok-Modell (grok --model). Default: Grok-Standard.

.PARAMETER MaxTurns
    Obergrenze Agent-Turns. Default: 40

.PARAMETER DryRun
    Zeigt nur den Grok-Aufruf, fuehrt ihn nicht aus.

.EXAMPLE
    .\dual-build.ps1 -Variants 3
#>
[CmdletBinding()]
param(
    [string]$Plan     = ".\PLAN.md",
    [int]   $Variants = 3,
    [string]$Branch   = "feat/poc",
    [string]$Into     = "main",
    [string]$Model    = "",
    [int]   $MaxTurns = 40,
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"  # PS 5.1: unter "Stop" terminiert nativer git-stderr faelschlich

function Fail($msg) { Write-Host "BLOCKED: $msg" -ForegroundColor Red; exit 1 }

# --- Phase 0: Preconditions ------------------------------------------------
if (-not (Get-Command grok -ErrorAction SilentlyContinue)) { Fail "grok CLI nicht im PATH." }
if (-not (Get-Command git  -ErrorAction SilentlyContinue)) { Fail "git nicht im PATH." }

git rev-parse --is-inside-work-tree 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "Kein git-Repo. Erst 'git init' + ersten Commit." }

if (-not (Test-Path $Plan)) { Fail "Contract fehlt: $Plan (Claude muss PLAN.md zuerst schreiben)." }
$planText = (Get-Content $Plan -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($planText)) { Fail "$Plan ist leer." }
if ($planText -match "<Feature-Name>|<Was soll gebaut") { Fail "$Plan ist noch das Template - erst ausfuellen." }

# PLAN.md muss committet sein, damit der worktree-Branch ihn enthaelt
$dirty = git status --porcelain $Plan
if ($dirty) { Fail "$Plan ist uncommitted. Erst committen, dann bauen." }

# --- Phase 1: Composed prompt ----------------------------------------------
$tmpDir = ".dual-agent\tmp"; $logDir = ".dual-agent\logs"
New-Item -ItemType Directory -Force -Path $tmpDir, $logDir | Out-Null
# Absolute Pfade: Grok wechselt mit --worktree das cwd -> ein relativer --prompt-file wuerde brechen.
$tmpAbs = (Resolve-Path $tmpDir).Path
$logAbs = (Resolve-Path $logDir).Path
$stamp     = Get-Date -Format "yyyyMMdd-HHmmss"
$promptFile = Join-Path $tmpAbs "prompt-$stamp.txt"
$logFile    = Join-Path $logAbs "grok-$stamp.log"

$instruction = @"
You are the BUILDER in a dual-agent workflow. Build a working POC that satisfies the
contract below EXACTLY. Do not exceed the Out-of-Scope section. Prefer the smallest
correct implementation. No secrets, no network unless the contract allows it.
A reviewer will harden your output afterwards - make it clean and honest, not padded.

=== CONTRACT (PLAN.md) ===
$planText
"@
Set-Content -Path $promptFile -Value $instruction -Encoding utf8

# --- Phase 2: isolierten worktree SELBST anlegen + Grok via --cwd ----------
# WICHTIG: grok --worktree greift im Headless-Modus NICHT (verifiziert) -> Grok baut sonst
# im Main-Tree. Wir legen den worktree selbst an und schicken Grok mit --cwd hinein.
$wtPath = Join-Path (Split-Path -Parent (Get-Location).Path) ("wt-" + ($Branch -replace '[\\/:]', '-'))

$grokArgs = @(
    "--cwd", $wtPath,
    "--prompt-file", $promptFile,
    "--output-format", "json",
    "--always-approve",
    "--max-turns", "$MaxTurns"
)
if ($Variants -gt 1) { $grokArgs += @("--best-of-n", "$Variants") }
if ($Model)          { $grokArgs += @("--model", $Model) }

Write-Host "=== Dual-Agent / Render (Grok) ===" -ForegroundColor Cyan
Write-Host "Contract : $Plan"
Write-Host "Branch   : $Branch  (worktree: $wtPath)"
Write-Host "Variants : $Variants"
Write-Host "Log      : $logFile"
Write-Host "Aufruf   : grok $($grokArgs -join ' ')"

if ($DryRun) { Write-Host "DryRun - kein Aufruf." -ForegroundColor Yellow; exit 0 }

# frischen worktree anlegen (alten Branch/worktree gleichen Namens vorher raeumen)
git worktree remove --force $wtPath 2>$null | Out-Null
git branch -D $Branch 2>$null | Out-Null
git worktree add -b $Branch $wtPath $Into 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "worktree add fehlgeschlagen ($Branch von $Into)." }

& grok @grokArgs *>&1 | Tee-Object -FilePath $logFile
$grokExit = $LASTEXITCODE

# --- Phase 3: Handoff to Claude (Assess + Fortify) -------------------------
Write-Host "`n=== Render fertig (grok exit=$grokExit) ===" -ForegroundColor Cyan
Write-Host "Worktree-Pfad: $wtPath"
# POC als Commit sichern: das Merge-Gate merged Branch-Commits, nicht nur working-tree-Aenderungen.
git -C $wtPath add -A 2>$null | Out-Null
if (git -C $wtPath status --porcelain) {
    git -C $wtPath commit -q -m "poc: grok build $stamp" 2>$null | Out-Null
    Write-Host "Uncommittete POC-Aenderungen auf $Branch committet."
}
Write-Host "`nDiff-Stat (POC vs ${Into}):"
git -C $wtPath diff --stat $Into 2>$null
Write-Host "`nNAECHSTE SCHRITTE fuer Claude (CRAFT A+F):" -ForegroundColor Green
Write-Host "  1. Review als untrusted code: git -C `"$wtPath`" diff $Into"
Write-Host "  2. Gegen PLAN.md pruefen (Drift / erfundene APIs / Error-Handling)."
Write-Host "  3. Haerten + Merge: dual-merge.ps1 -From $Branch -Into $Into -Verify `"<test>`""

if ($grokExit -ne 0) { Write-Host "Hinweis: grok exit != 0 (Refusal/Tool-Fehler?) - Log lesen." -ForegroundColor Yellow }
