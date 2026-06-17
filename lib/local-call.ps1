<#
.SYNOPSIS
    Zero-quota local Ollama wrapper (scout builder) -- same contract as grok-call.ps1.

.DESCRIPTION
    Runs a prompt against a local Ollama model (localhost:11434) for $0 and ZERO subscription
    quota. Use it as an extra best-of-n variant source or for mechanical/scout passes -- NEVER for
    the merge-gating ASSESS (that must stay frontier; the cross-vendor moat needs a strong reviewer).
    Quality-safe because every local output is downstream-gated by pass^k / a JSON-schema check, so
    a weak local variant simply loses the tournament; nothing reaches main unverified.

    Returns the grok-call contract: ExitCode, Text, Json, StdoutLog (+ Model, Vendor).
    Returns $null with a BLOCKED error if Ollama is unreachable (missing-service, fail honest).

.PARAMETER PromptFile  Path to the prompt file.
.PARAMETER Model       Ollama model tag (e.g. qwen2.5-coder:7b). Set to one you have pulled.
.PARAMETER Temperature Sampling temperature. Default 0.2 (format adherence ~deterministic).
.PARAMETER Json        Request JSON-formatted output (Ollama format:json) for schema-gated passes.
.PARAMETER Endpoint    Ollama chat endpoint. Default http://localhost:11434/api/chat.
.PARAMETER Tag         Log-file prefix.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PromptFile,
    [string]$Model       = "qwen2.5:7b",
    [double]$Temperature = 0.2,
    [switch]$Json,
    [string]$Endpoint    = "http://localhost:11434/api/chat",
    [int]   $TimeoutSec  = 120,
    [string]$Tag         = "local"
)
$ErrorActionPreference = "Continue"
if (-not (Test-Path $PromptFile)) { Write-Error "BLOCKED: prompt file missing: $PromptFile"; return $null }

$repoRoot = Split-Path -Parent $PSScriptRoot
$logDir   = Join-Path $repoRoot ".dual-agent\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stamp    = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$outFile  = Join-Path $logDir "$Tag-$stamp.out.json"

$promptText = Get-Content $PromptFile -Raw
# Defensive: PS 5.1 -Raw can carry a BOM / trailing CRLF that Ollama's /api/chat rejects (400).
if ($promptText) { $promptText = $promptText.TrimStart([char]0xFEFF).Trim() }
$body = @{
    model    = $Model
    messages = @(@{ role = "user"; content = $promptText })
    stream   = $false
    options  = @{ temperature = $Temperature }
}
if ($Json) { $body.format = "json" }
$bodyJson = $body | ConvertTo-Json -Depth 6

$text = ""; $exit = 0; $jsonResp = $null   # NOTE: not $json -- that collides with the [switch]$Json param (PS is case-insensitive)
try {
    $resp = Invoke-RestMethod -Uri $Endpoint -Method Post -Body $bodyJson -ContentType "application/json" -TimeoutSec $TimeoutSec -ErrorAction Stop
    if ($resp.message -and $resp.message.content) { $text = $resp.message.content }
    $jsonResp = $resp
    Set-Content -Path $outFile -Value ($resp | ConvertTo-Json -Depth 8) -Encoding utf8
} catch {
    $exit = 1
    Write-Error ("BLOCKED: Ollama unreachable/failed at {0} ({1}). Run 'ollama serve' + pull model '{2}'." -f $Endpoint, $_.Exception.Message, $Model)
}

[PSCustomObject]@{
    ExitCode  = $exit
    Text      = $text
    Json      = $jsonResp
    StdoutLog = $outFile
    Model     = $Model
    Vendor    = "ollama-local"
}
