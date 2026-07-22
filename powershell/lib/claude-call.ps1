<#
.SYNOPSIS
    Clean wrapper for ONE headless Claude invocation (dual-agent foundation).

.DESCRIPTION
    The Claude-side twin of grok-call.ps1, so the bounded cross-review can run
    Claude headless symmetrically to Grok. Same three guarantees:
      1. stdout (the JSON result) and stderr separated at the OS level via
         Start-Process redirects -> no leakage, parseable result.
      2. Raw process bytes (UTF-8), never routed through PS Out-File (no UTF-16).
      3. --output-format json parsed; callers get .Json and .Text.
    The prompt is fed on STDIN (RedirectStandardInput) so long, multi-line review
    prompts with quotes/markdown survive intact (no arg-quoting hell).

    Returns a PSCustomObject: ExitCode, IsError, Stdout, Json, Text, SessionId, StdoutLog, StderrLog.
    Returns $null (with Write-Error) on a precondition failure.

.PARAMETER PromptFile    Absolute path to the prompt file (fed to claude on stdin).
.PARAMETER Model         claude --model (optional).
.PARAMETER SystemPrompt  Appended to the system prompt (--append-system-prompt) for role injection.
.PARAMETER Tag           Log-file name prefix. Default "claude".

.EXAMPLE
    $r = & .\lib\claude-call.ps1 -PromptFile (Resolve-Path .\ledger\review-prompt.txt) -SystemPrompt (Get-Content roles\critic.md -Raw)
    if ($r.ExitCode -eq 0 -and -not $r.IsError) { $r.Text }
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PromptFile,
    [string]$Model        = "",
    [string]$SystemPrompt = "",
    [double]$MaxBudgetUsd = 0,
    [string]$Tag          = "claude"
)
$ErrorActionPreference = "Continue"  # PS 5.1: native stderr must not terminate.

$claude = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claude)                 { Write-Error "BLOCKED: claude CLI not in PATH."; return $null }
if (-not (Test-Path $PromptFile)) { Write-Error "BLOCKED: prompt file missing: $PromptFile"; return $null }

$repoRoot = Split-Path -Parent $PSScriptRoot
$logDir   = Join-Path $repoRoot ".dual-agent\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stamp    = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$outFile  = Join-Path $logDir "$Tag-$stamp.out.json"
$errFile  = Join-Path $logDir "$Tag-$stamp.err.log"

# Headless print mode; prompt fed on stdin via pipe. `claude` is a .ps1/.cmd shim
# (npm at ...\npm\claude.ps1), NOT a Win32 exe -> Start-Process cannot launch it
# ("not a valid Win32 application"). The call operator + pipe is shim-compatible.
# No tools needed for a text review, so -p returns directly. stdout -> variable
# (clean UTF-8, no file-encoding step); stderr -> $errFile.
# --exclude-dynamic-system-prompt-sections: moves per-machine sections (cwd/env/memory paths) into
# the first user message so the ~100k system prefix becomes cache-shareable ACROSS worktrees (Claude's
# cache is per-directory; our worktree isolation defeats it by default). Quality-neutral: the cwd
# already travels inside our prompts. Verified present in this claude build.
$claudeArgs = @("-p", "--output-format", "json", "--exclude-dynamic-system-prompt-sections")
if ($Model)              { $claudeArgs += @("--model", $Model) }
if ($SystemPrompt)       { $claudeArgs += @("--append-system-prompt", $SystemPrompt) }
if ($MaxBudgetUsd -gt 0) { $claudeArgs += @("--max-budget-usd", "$MaxBudgetUsd") }  # native per-call cap

$promptText = Get-Content $PromptFile -Raw
$out  = $promptText | & claude @claudeArgs 2>$errFile
$exit = $LASTEXITCODE
$stdout = ($out -join "`n")
if ($null -eq $stdout) { $stdout = "" }
# Persist a UTF-8 copy of the result for audit (deliberately NOT the UTF-16 `1>` path).
Set-Content -Path $outFile -Value $stdout -Encoding utf8

$json = $null
if ($stdout.Trim()) {
    try { $json = $stdout | ConvertFrom-Json }
    catch {
        $last = ($stdout -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
        if ($last) { try { $json = $last | ConvertFrom-Json } catch { } }
    }
}

# claude -p --output-format json shape: { type, subtype, result, session_id, is_error, ... }
$text     = $stdout
$isError  = $false
$sessionId = ""
if ($json) {
    foreach ($p in 'result','response','output','text','content','message') {
        if ($json.PSObject.Properties[$p]) { $text = $json.$p; break }
    }
    if ($json.PSObject.Properties['is_error'])   { $isError   = [bool]$json.is_error }
    if ($json.PSObject.Properties['session_id']) { $sessionId = $json.session_id }
}
# Cost telemetry: capture the per-call spend and append one line to ledger\SPEND.jsonl -- the
# deterministic basis for a budget guard (and to measure that the cache flag is actually saving).
$cost = $null
if ($json -and $json.PSObject.Properties['total_cost_usd']) { $cost = $json.total_cost_usd }
if ($null -ne $cost) {
    $ledgerDir = Join-Path $repoRoot "ledger"; New-Item -ItemType Directory -Force -Path $ledgerDir | Out-Null
    ([PSCustomObject]@{ stamp=$stamp; tag=$Tag; model=$Model; cost_usd=$cost } | ConvertTo-Json -Compress) |
        Add-Content -Path (Join-Path $ledgerDir "SPEND.jsonl") -Encoding utf8
}

[PSCustomObject]@{
    ExitCode  = $exit
    IsError   = $isError
    SessionId = $sessionId
    Cost      = $cost
    Stdout    = $stdout
    Json      = $json
    Text      = $text
    StdoutLog = $outFile
    StderrLog = $errFile
}
