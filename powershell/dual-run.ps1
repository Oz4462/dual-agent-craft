# dual-run.ps1 — Windows entrypoint for the full bash dual-run / team path.
#
# Prefers (in order):
#   1) bash on PATH (Git Bash, MSYS)
#   2) Git\bin\bash.exe standard install locations
#   3) wsl.exe running the repo scripts
#
# Usage (PowerShell):
#   .\powershell\dual-run.ps1 --status
#   .\powershell\dual-run.ps1 --dry-run --verify "true" --skip-merge
#   .\powershell\dual-run.ps1 --task "feature" --verify "py -3 -m pytest -q"
#
# All arguments after the script name are forwarded to dual-run.sh unchanged.
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ArgsForward
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $RepoRoot "dual-run.sh"))) {
    Write-Host "BLOCKED: dual-run.sh not found under $RepoRoot" -ForegroundColor Red
    exit 1
}

function Find-Bash {
    $cmd = Get-Command bash -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        "${env:ProgramFiles}\Git\bin\bash.exe",
        "${env:ProgramFiles}\Git\usr\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return $null
}

$bash = Find-Bash
$argLine = ($ArgsForward | ForEach-Object {
    if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
}) -join ' '

if ($bash) {
    Write-Host "Using bash: $bash" -ForegroundColor DarkGray
    # Git Bash needs POSIX path for -lc cwd; pass script as absolute unix-ish path.
    $script = (Join-Path $RepoRoot "dual-run.sh") -replace '\\', '/'
    if ($script -match '^([A-Za-z]):/') {
        $drive = $Matches[1].ToLower()
        $script = "/$drive" + $script.Substring(2)
    }
    $repoUnix = $RepoRoot -replace '\\', '/'
    if ($repoUnix -match '^([A-Za-z]):/') {
        $drive = $Matches[1].ToLower()
        $repoUnix = "/$drive" + $repoUnix.Substring(2)
    }
    & $bash -lc "cd '$repoUnix' && bash './dual-run.sh' $argLine"
    exit $LASTEXITCODE
}

$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if ($wsl) {
    Write-Host "bash not found — falling back to WSL" -ForegroundColor Yellow
    # Convert Windows path to /mnt/<drive>/...
    $drive = $RepoRoot.Substring(0, 1).ToLower()
    $tail = $RepoRoot.Substring(2) -replace '\\', '/'
    $wslPath = "/mnt/$drive$tail"
    $cmd = "cd '$wslPath' && bash ./dual-run.sh $argLine"
    & wsl.exe -e bash -lc $cmd
    exit $LASTEXITCODE
}

Write-Host @"
BLOCKED: No bash found for the full dual-run / team path.

Install one of:
  - Git for Windows (https://git-scm.com)  → re-open PowerShell and retry
  - WSL2 Ubuntu                            → wsl --install

Classic CRAFT without team-work still works in pure PowerShell:
  .\powershell\dual-build.ps1 ...
  .\powershell\dual-review.ps1 ...
  .\powershell\dual-merge.ps1 ...

See PLATFORM.md for the full matrix.
"@ -ForegroundColor Red
exit 1
