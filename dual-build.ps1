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
    [switch]$Adaptive,            # render N=1 first, escalate to -Variants only on failed acceptance
    [string]$Verify   = "",       # cheap acceptance signal for adaptive escalation (e.g. "pytest -q")
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

# Render laeuft jetzt ueber lib\grok-call.ps1: es baut die grok-Args UND trennt
# stdout(json) von stderr(noise) auf OS-Ebene. Der alte Inline-Filter (*>&1 |
# Where-Object) scheiterte still an PS-5.1-ErrorRecords -> Auth-Spam landete im
# (UTF-16-)Log. grok-call schreibt grok-*.out.json + grok-*.err.log getrennt.

Write-Host "=== Dual-Agent / Render (Grok) ===" -ForegroundColor Cyan
Write-Host "Contract : $Plan"
Write-Host "Branch   : $Branch  (worktree: $wtPath)"
Write-Host "Variants : $Variants"
Write-Host "Log-Dir  : $logDir  (grok-*.out.json + grok-*.err.log getrennt)"
Write-Host "Render   : lib\grok-call.ps1 -BestOfN $Variants  (stdout/stderr OS-getrennt)"

if ($DryRun) { Write-Host "DryRun - kein Aufruf." -ForegroundColor Yellow; exit 0 }

# WIP-Basis sichern: ein worktree branched von einem COMMIT, nicht vom working-tree.
# Damit Grok die aktuelle (uncommittete) Arbeit sieht, committen wir WIP zuerst auf einen
# Feature-Branch (kein Push); $Into bleibt sauber. Fliessend, kein manueller git-Tanz.
if (git status --porcelain) {
    $curBranch = (git rev-parse --abbrev-ref HEAD).Trim()
    if ($curBranch -eq $Into) {
        $wipBranch = "feat/wip-$stamp"
        git switch -c $wipBranch 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "konnte WIP-Feature-Branch $wipBranch nicht anlegen." }
        Write-Host "WIP -> neuer Feature-Branch $wipBranch ($Into bleibt sauber, kein Push)." -ForegroundColor DarkCyan
    } else {
        $wipBranch = $curBranch
    }
    git add -A
    git commit -q -m "wip: dual-agent base $stamp [no-push]" 2>$null | Out-Null
    Write-Host "WIP committet auf $wipBranch -> Grok sieht die aktuelle Basis." -ForegroundColor DarkCyan
}

# frischen worktree anlegen (von HEAD = aktuelle Basis inkl. WIP), alten gleichnamigen raeumen
git worktree remove --force $wtPath 2>$null | Out-Null
git branch -D $Branch 2>$null | Out-Null
git worktree add -b $Branch $wtPath HEAD 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "worktree add fehlgeschlagen ($Branch von HEAD)." }

# Render: stdout(json)/stderr(noise) werden in grok-call.ps1 OS-seitig getrennt
# (Start-Process-Redirects). Kein fragiler Stream-Merge, kein UTF-16-Log mehr.
# Least-privilege: --always-approve keeps headless autonomous, but --deny blocks destructive/
# exfiltrative ops (deny overrides approve). Exact grok rule syntax confirmed on first live render.
$denyRules = @('Bash(rm -rf *)', 'Bash(git push *)', 'Bash(curl *)', 'Bash(wget *)')
$doRender = {
    param($n)
    & "$PSScriptRoot\lib\grok-call.ps1" -PromptFile $promptFile -Cwd $wtPath `
        -MaxTurns $MaxTurns -BestOfN $n -Model $Model -AlwaysApprove -Deny $denyRules -Tag "grok"
}
# Adaptive: render the cheap N=1 first; escalate to full -Variants ONLY if it fails acceptance.
# ~66% fewer Grok tokens on easy builds, equal quality (the eval still gates the merge).
$effectiveN = if ($Adaptive -and $Variants -gt 1) { 1 } else { $Variants }
Write-Host ("Render   : best-of-{0}{1}" -f $effectiveN, $(if ($Adaptive) { ' (adaptive: N=1 first)' } else { '' }))
$render = & $doRender $effectiveN
$grokExit = if ($render) { $render.ExitCode } else { 1 }
if ($render) {
    Write-Host "`nGrok-Resultat (stdout, noise-frei):" -ForegroundColor DarkCyan
    Write-Host ("$($render.Text)".Trim())
    Write-Host "`nVoll-Log: $($render.StdoutLog)"
    Write-Host "stderr/noise (separat): $($render.StderrLog)"
    if ($render.NoiseInResult) { Write-Host "WARN: Noise im Resultat erkannt (unerwartet -> grok-call pruefen)." -ForegroundColor Yellow }
} else {
    Write-Host "BLOCKED: grok-call.ps1 lieferte kein Resultat (Praecondition?)." -ForegroundColor Red
}

# Adaptive escalation: if the cheap N=1 build fails the acceptance signal, re-render with full N.
if ($Adaptive -and $Variants -gt 1 -and $Verify -and $grokExit -eq 0) {
    Push-Location $wtPath
    $acceptOk = $true
    try { Invoke-Expression $Verify *> $null; if ($LASTEXITCODE -ne 0) { $acceptOk = $false } } catch { $acceptOk = $false }
    Pop-Location
    if (-not $acceptOk) {
        Write-Host ("Adaptive : N=1 failed acceptance ({0}) -> escalating to best-of-{1}" -f $Verify, $Variants) -ForegroundColor Yellow
        $render = & $doRender $Variants
        $grokExit = if ($render) { $render.ExitCode } else { 1 }
    } else {
        Write-Host ("Adaptive : N=1 passed acceptance -> saved {0} variants." -f ($Variants - 1)) -ForegroundColor Green
    }
}

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
