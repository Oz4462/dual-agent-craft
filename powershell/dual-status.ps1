# dual-status.ps1 — Windows bridge to dual-status.sh (or minimal doctor if no bash).
$ErrorActionPreference = "Continue"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$bash = $null
$cmd = Get-Command bash -ErrorAction SilentlyContinue
if ($cmd) { $bash = $cmd.Source }
if (-not $bash) {
    foreach ($c in @(
        "${env:ProgramFiles}\Git\bin\bash.exe",
        "${env:ProgramFiles}\Git\usr\bin\bash.exe"
    )) { if (Test-Path $c) { $bash = $c; break } }
}
if ($bash) {
    $repoUnix = $RepoRoot -replace '\\', '/'
    if ($repoUnix -match '^([A-Za-z]):/') {
        $drive = $Matches[1].ToLower()
        $repoUnix = "/$drive" + $repoUnix.Substring(2)
    }
    & $bash -lc "cd '$repoUnix' && bash ./dual-status.sh"
    exit $LASTEXITCODE
}
Write-Host "=== dual-agent status (PowerShell fallback) ===" -ForegroundColor Cyan
foreach ($c in @('git','python','python3','claude','grok','codex','bash','wsl')) {
    $x = Get-Command $c -ErrorAction SilentlyContinue
    if ($x) { Write-Host "  ok    $c" -ForegroundColor Green }
    else { Write-Host "  --    $c" -ForegroundColor Yellow }
}
Write-Host "Install Git Bash or WSL for full dual-status.sh. See PLATFORM.md."
