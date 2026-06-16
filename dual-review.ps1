<#
.SYNOPSIS
    Bounded cross-review (CRAFT step A) -- the consensus-free debate mechanism.

.DESCRIPTION
    NOT "debate-until-consensus" (research-backed harmful: sycophantic conformity).
    Instead: ONE structured cross-examination, then the EVAL decides.
      1. ASSESS  : Claude reviews the Builder's diff as untrusted code -> JSON issues[].
      2. REBUTTAL: Grok answers each issue once (concede | defend+evidence) -> JSON rebuttals[].
    Hard cap: ONE rebuttal round (no rhetoric loop). Then every issue lands in one of:
      - conceded            -> Grok fixes it in the next feat/poc build turn.
      - defended + decidable -> the EVAL (pass^k on acceptance/adversarial tests) decides.
                                Neither agent wins by argument; the test does.
      - defended + subjective -> TIE -> tie-break (c): Grok builds BOTH variants as a
                                micro-probe and eval-harness measures the winner (dual-tiebreak.ps1).
    Cross-vendor by construction: Claude (reviewer) and Grok (builder) are different
    model families, so this breaks correlated errors + self-preference bias (MoA / PoLL).

    Writes ledger\REVIEW.md (human record) + ledger\REVIEW.json (machine) and updates HANDOFF.

.PARAMETER Plan        Contract file. Default .\PLAN.md
.PARAMETER PocBranch   Branch holding the Builder's POC. Default feat/poc
.PARAMETER Base        Baseline branch the diff is taken against. Default main
.PARAMETER Model       Optional grok model for the rebuttal turn.
.PARAMETER DryRun      Assemble prompts + show the flow, but make NO billed CLI calls.

.EXAMPLE
    .\dual-review.ps1 -PocBranch feat/poc -Base main
#>
[CmdletBinding()]
param(
    [string]$Plan      = ".\PLAN.md",
    [string]$PocBranch = "feat/poc",
    [string]$Base      = "main",
    [string]$Model     = "",
    [switch]$DryRun
)
$ErrorActionPreference = "Continue"  # PS 5.1: native git/CLI stderr must not terminate.
function Fail($m) { Write-Host "BLOCKED: $m" -ForegroundColor Red; exit 1 }

# Robustly pull a JSON object out of a model reply (may be fenced or prose-wrapped).
function Extract-Json([string]$s) {
    if (-not $s) { return $null }
    $t = $s -replace '(?s)```json', '' -replace '(?s)```', ''
    $i = $t.IndexOf('{'); $j = $t.LastIndexOf('}')
    if ($i -lt 0 -or $j -le $i) { return $null }
    $cand = $t.Substring($i, $j - $i + 1)
    try { return $cand | ConvertFrom-Json } catch { return $null }
}

# --- Phase 0: Preconditions ------------------------------------------------
git rev-parse --is-inside-work-tree 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "Kein git-Repo." }
if (-not (Test-Path $Plan)) { Fail "Contract fehlt: $Plan (erst PLAN.md schreiben)." }
git rev-parse --verify $PocBranch 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "POC-Branch fehlt: $PocBranch (erst dual-build.ps1)." }
git rev-parse --verify $Base 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "Base-Branch fehlt: $Base." }

$planText = (Get-Content $Plan -Raw).Trim()
$diff = (git diff "$Base...$PocBranch" | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($diff)) { Fail "Leerer Diff ($Base...$PocBranch) - nichts zu reviewen (empty-branch?)." }

$repoRoot = (Get-Location).Path
$tmpDir   = Join-Path $repoRoot ".dual-agent\tmp"
$ledger   = Join-Path $repoRoot "ledger"
New-Item -ItemType Directory -Force -Path $tmpDir, $ledger | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"

# --- Phase 1: ASSESS prompt (Claude, untrusted-code lens) ------------------
$assessPrompt = @"
You are the REVIEWER in a dual-agent build. Review the BUILDER's diff below as UNTRUSTED
external code against the CONTRACT. Flag only substantive problems (drift from the contract,
invented/hallucinated APIs, missing error handling, security, real defects). Cite the file.
Output ONLY a JSON object - no prose, no markdown fences:
{"issues":[{"id":"I1","severity":"high|med|low","file":"path","kind":"drift|invented-api|missing-error|security|style","claim":"one sentence","eval_decidable":true}]}
Set eval_decidable=true if an acceptance/adversarial TEST could objectively prove who is right;
false if it is subjective (naming/structure/taste). If the diff is clean, output {"issues":[]}.

=== CONTRACT (PLAN.md) ===
$planText

=== BUILDER DIFF (untrusted, $Base...$PocBranch) ===
$diff
"@
$assessFile = Join-Path $tmpDir "review-assess-$stamp.txt"
Set-Content -Path $assessFile -Value $assessPrompt -Encoding utf8

Write-Host "=== Dual-Agent / Bounded Cross-Review (CRAFT A) ===" -ForegroundColor Cyan
Write-Host "Contract : $Plan"
Write-Host "Diff     : $Base...$PocBranch  ($(($diff -split "`n").Count) Zeilen)"
Write-Host "Mechanik : 1 Assess (Claude) + 1 Rebuttal (Grok), dann entscheidet der Eval. Kein Loop."
Write-Host "Assess-Prompt: $assessFile"

if ($DryRun) {
    Write-Host "`nDryRun - keine CLI-Calls. Naechster echter Lauf ruft claude-call + grok-call." -ForegroundColor Yellow
    Write-Host "Erwartet: Claude -> issues[] (JSON), Grok -> rebuttals[] (JSON), Klassifikation + ledger\REVIEW.md."
    exit 0
}

# --- Phase 2: ASSESS (Claude headless) -------------------------------------
Write-Host "`n[A] Claude reviewt (untrusted) ..." -ForegroundColor DarkCyan
$ar = & "$PSScriptRoot\lib\claude-call.ps1" -PromptFile $assessFile -Tag "review-assess"
if (-not $ar -or $ar.ExitCode -ne 0) { Fail "claude-call (Assess) fehlgeschlagen." }
$assess = Extract-Json $ar.Text
if (-not $assess -or -not $assess.PSObject.Properties['issues']) { Fail "Claude lieferte kein issues-JSON. Roh: $($ar.Text)" }
$issues = @($assess.issues)
Write-Host ("    {0} Issue(s) gemeldet." -f $issues.Count)

if ($issues.Count -eq 0) {
    @{ stamp=$stamp; issues=@(); rebuttals=@(); verdict="clean" } | ConvertTo-Json -Depth 6 |
        Set-Content (Join-Path $ledger "REVIEW.json") -Encoding utf8
    Write-Host "Sauberer Diff - kein Streit. BATON -> gate (Eval entscheidet Merge)." -ForegroundColor Green
    exit 0
}

# --- Phase 3: REBUTTAL (Grok headless, exactly ONE round) ------------------
$issuesJson = ($issues | ConvertTo-Json -Depth 6)
$rebuttalPrompt = @"
You are the BUILDER. The REVIEWER raised the issues below about YOUR diff. For EACH issue,
either "concede" (you will fix it), "defend" with a REAL citation, or "unsure". A "defend"
REQUIRES a citation token: a PLAN clause id, a documentation URL, or a test name. If you cannot
ground a defense, answer "unsure" -- this is NOT a loss, it routes the item to the eval. Do NOT
bluff a defend without a citation (anti-hallucination). Do NOT be sycophantic: defend correct
code, concede real problems. This is your ONLY rebuttal turn. Output ONLY a JSON object - no
prose, no fences:
{"rebuttals":[{"id":"I1","verdict":"concede|defend|unsure","citation":"PLAN-clause|doc-URL|test-name|none","reason":"one sentence"}]}

=== CONTRACT (PLAN.md) ===
$planText

=== YOUR DIFF ($Base...$PocBranch) ===
$diff

=== REVIEWER ISSUES ===
$issuesJson
"@
$rebFile = Join-Path $tmpDir "review-rebuttal-$stamp.txt"
Set-Content -Path $rebFile -Value $rebuttalPrompt -Encoding utf8

Write-Host "[R] Grok antwortet (1 Runde, kein Loop) ..." -ForegroundColor DarkCyan
$rr = & "$PSScriptRoot\lib\grok-call.ps1" -PromptFile $rebFile -Cwd $repoRoot -MaxTurns 6 -AlwaysApprove -Model $Model -Tag "review-rebuttal"
if (-not $rr -or $rr.ExitCode -ne 0) { Fail "grok-call (Rebuttal) fehlgeschlagen." }
$reb = Extract-Json $rr.Text
$rebuttals = if ($reb -and $reb.PSObject.Properties['rebuttals']) { @($reb.rebuttals) } else { @() }
Write-Host ("    {0} Rebuttal(s)." -f $rebuttals.Count)

# --- Phase 4: Classify (the eval decides; subjective ties -> micro-probe) ---
$conceded = @(); $evalDecides = @(); $ties = @(); $unsure = @()
foreach ($iss in $issues) {
    $rb = $rebuttals | Where-Object { $_.id -eq $iss.id } | Select-Object -First 1
    $verdict  = if ($rb) { "$($rb.verdict)".ToLower() } else { "defend" }  # no answer = treat as defended
    $citation = if ($rb -and $rb.PSObject.Properties['citation']) { "$($rb.citation)".Trim().ToLower() } else { "" }
    # Grounding gate: a "defend" with no real citation auto-downgrades to "unsure" (anti-hallucination).
    if ($verdict -eq "defend" -and ($citation -eq "" -or $citation -eq "none")) { $verdict = "unsure" }
    if ($verdict -eq "concede") {
        $conceded += $iss
    } elseif ($verdict -eq "unsure") {
        $unsure += $iss           # ungrounded -> route to eval / contract clarification, not a bluffed defense
    } elseif ($iss.eval_decidable) {
        $evalDecides += $iss      # objective: the acceptance/adversarial test settles it
    } else {
        $ties += $iss             # subjective + grounded-defend -> tie-break (c) micro-probe
    }
}

# --- Phase 5: Ledger -------------------------------------------------------
$record = [PSCustomObject]@{
    stamp=$stamp; base=$Base; poc=$PocBranch
    issues=$issues; rebuttals=$rebuttals
    conceded=@($conceded.id); eval_decides=@($evalDecides.id); ties=@($ties.id); unsure=@($unsure.id)
    verdict = if ($ties.Count) { "tie-break-needed" } elseif ($unsure.Count) { "clarify-unknowns" } elseif ($evalDecides.Count) { "eval-decides" } else { "fixes-pending" }
}
$record | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $ledger "REVIEW.json") -Encoding utf8

$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("# REVIEW -- $stamp  ($Base...$PocBranch)")
[void]$md.AppendLine("")
[void]$md.AppendLine("Mechanik: bounded cross-review (1 Assess + 1 Rebuttal). Der Eval entscheidet, nicht Konsens.")
[void]$md.AppendLine("")
[void]$md.AppendLine("## Conceded (Grok fixt im naechsten Build): $($conceded.Count)")
foreach ($i in $conceded) { [void]$md.AppendLine("- [$($i.id)] $($i.file): $($i.claim)") }
[void]$md.AppendLine("")
[void]$md.AppendLine("## Eval entscheidet (objektiv, pass^k auf Tests): $($evalDecides.Count)")
foreach ($i in $evalDecides) { [void]$md.AppendLine("- [$($i.id)] $($i.file): $($i.claim)") }
[void]$md.AppendLine("")
[void]$md.AppendLine("## Ties -> Mikro-Probe (dual-tiebreak.ps1, Wahl c): $($ties.Count)")
foreach ($i in $ties) { [void]$md.AppendLine("- [$($i.id)] $($i.file): $($i.claim)") }
[void]$md.AppendLine("")
[void]$md.AppendLine("## Unsure (ungegroundet -> Eval/Contract-Klaerung statt Bluff): $($unsure.Count)")
foreach ($i in $unsure) { [void]$md.AppendLine("- [$($i.id)] $($i.file): $($i.claim)") }
Set-Content (Join-Path $ledger "REVIEW.md") -Value ($md.ToString()) -Encoding utf8

Write-Host "`n=== Review fertig ===" -ForegroundColor Cyan
Write-Host ("  conceded={0}  eval-decides={1}  ties={2}  unsure={3}" -f $conceded.Count, $evalDecides.Count, $ties.Count, $unsure.Count)
Write-Host "  Ledger: ledger\REVIEW.md + ledger\REVIEW.json"
if ($ties.Count) {
    Write-Host "  NAECHSTES: dual-tiebreak.ps1 fuer $($ties.Count) subjektive(s) Tie(s) (Mikro-Probe + Eval)." -ForegroundColor Yellow
} else {
    Write-Host "  NAECHSTES: Grok fixt conceded -> dual-merge.ps1 -EvalK 5 (Eval entscheidet)." -ForegroundColor Green
}
