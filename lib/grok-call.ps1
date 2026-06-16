<#
.SYNOPSIS
    Clean wrapper for ONE headless Grok invocation (dual-agent foundation).

.DESCRIPTION
    Fixes three bugs verified against the saved .dual-agent\logs\grok-*.log:
      1. stdout (the JSON result) and stderr (auth/MCP noise) are separated at the
         OS level via Start-Process redirects -> the HuggingFace/AuthorizationRequired
         spam can NEVER leak into the parsed result. The old `& grok ... *>&1 | Where-Object`
         filter silently failed because PS 5.1 wraps native stderr in ErrorRecords,
         so "$_" was never the clean line the regex expected.
      2. Streams are the raw process bytes (grok emits UTF-8), NOT routed through
         PS Out-File (`1>file`), which defaults to UTF-16LE and produced the
         null-byte-interleaved logs that ASCII tooling cannot parse.
      3. --output-format json is parsed into an object; callers get .Json and .Text.

    Returns a PSCustomObject: ExitCode, Stdout, Json, Text, StdoutLog, StderrLog, NoiseInResult.
    Returns $null (with Write-Error) on a precondition failure.

.PARAMETER PromptFile  Absolute path to the prompt file (grok changes cwd, relative breaks).
.PARAMETER Cwd         Working dir for grok. Use an isolated worktree for real builds.
.PARAMETER MaxTurns    Agent turn cap. Default 40.
.PARAMETER BestOfN     Parallel variants (grok --best-of-n, headless only). Default 1.
.PARAMETER Model       grok --model (grok-build | grok-composer-2.5-fast). Default: grok default.
.PARAMETER Sandbox     grok --sandbox profile (filesystem/network restriction).
.PARAMETER AlwaysApprove  Auto-approve tool executions (only inside an isolated worktree).
.PARAMETER Check       Append grok's self-verification loop (--check).
.PARAMETER Tag         Log-file name prefix. Default "grok".

.EXAMPLE
    $r = & .\lib\grok-call.ps1 -PromptFile (Resolve-Path .\PLAN.md) -Cwd $wt -BestOfN 3 -AlwaysApprove
    if ($r.ExitCode -eq 0 -and -not $r.NoiseInResult) { $r.Text }
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PromptFile,
    [string]$Cwd          = (Get-Location).Path,
    [int]   $MaxTurns     = 40,
    [int]   $BestOfN      = 1,
    [string]$Model        = "",
    [string]$Sandbox      = "",
    [switch]$AlwaysApprove,
    [switch]$Check,
    [string]$Tag          = "grok"
)
$ErrorActionPreference = "Continue"  # PS 5.1: native stderr must not terminate.

$grok = Get-Command grok -ErrorAction SilentlyContinue
if (-not $grok)                  { Write-Error "BLOCKED: grok CLI not in PATH."; return $null }
if (-not (Test-Path $PromptFile)){ Write-Error "BLOCKED: prompt file missing: $PromptFile"; return $null }

$repoRoot = Split-Path -Parent $PSScriptRoot
$logDir   = Join-Path $repoRoot ".dual-agent\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stamp    = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$outFile  = Join-Path $logDir "$Tag-$stamp.out.json"
$errFile  = Join-Path $logDir "$Tag-$stamp.err.log"

# Build the argument string; quote every path because --cwd changes the working dir.
$a = "--prompt-file `"$PromptFile`" --cwd `"$Cwd`" --output-format json --max-turns $MaxTurns"
if ($BestOfN -gt 1) { $a += " --best-of-n $BestOfN" }
if ($AlwaysApprove) { $a += " --always-approve" }
if ($Check)         { $a += " --check" }
if ($Model)         { $a += " --model `"$Model`"" }
if ($Sandbox)       { $a += " --sandbox `"$Sandbox`"" }

# OS-level stream separation: result -> $outFile (raw UTF-8), noise -> $errFile.
$proc = Start-Process -FilePath $grok.Source -ArgumentList $a `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile
$exit = $proc.ExitCode

$stdout = if (Test-Path $outFile) { Get-Content $outFile -Raw -Encoding UTF8 } else { "" }
if ($null -eq $stdout) { $stdout = "" }

# Parse JSON: whole payload first, else the last non-empty line (trailing object).
$json = $null
if ($stdout.Trim()) {
    try { $json = $stdout | ConvertFrom-Json }
    catch {
        $last = ($stdout -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
        if ($last) { try { $json = $last | ConvertFrom-Json } catch { } }
    }
}

# Extract the agent text from the common grok json shapes; fall back to raw stdout.
$text = $stdout
if ($json) {
    foreach ($p in 'result','response','output','text','content','message') {
        if ($json.PSObject.Properties[$p]) { $text = $json.$p; break }
    }
}

# Honest self-check: the noise MUST live in stderr, never in the parsed result.
$noisePattern  = 'AuthorizationRequired|Transport channel closed|huggingface\.co|www_authenticate'
$noiseInResult = [bool]($stdout -match $noisePattern)

[PSCustomObject]@{
    ExitCode      = $exit
    Stdout        = $stdout
    Json          = $json
    Text          = $text
    StdoutLog     = $outFile
    StderrLog     = $errFile
    NoiseInResult = $noiseInResult
}
