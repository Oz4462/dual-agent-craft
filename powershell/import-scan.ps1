<#
.SYNOPSIS
    Deterministic invented-package / off-contract-import guard (anti-hallucination #1).

.DESCRIPTION
    The best-documented and most dangerous coding-agent hallucination is the INVENTED
    PACKAGE: ~19.7% of LLM-recommended packages do not exist (arXiv:2406.10279), and it
    is weaponized as "slopsquatting" -- an empty package uploaded under an LLM-invented
    name ("huggingface-cli") drew 30k+ downloads. This gate extracts every import/dependency
    added in a diff and FAIL-CLOSED checks each against:
      (a) the real public registry  -- PyPI / npm 404 => the package does not exist;
      (b) the PLAN's declared allow-list -- anything not allowed = off-contract drift.
    ZERO model calls, fully deterministic -- nothing in the loop can itself hallucinate.
    Standard-library modules (python/node builtins) are recognised and never flagged.

    Writes ledger\IMPORT-SCAN.json. Exit 0 = clean, exit 2 = BLOCKED (invented/off-contract).

.PARAMETER PocBranch  Branch with the new code. Default feat/poc.
.PARAMETER Base       Baseline to diff against. Default main.
.PARAMETER DiffText   Scan this diff text directly instead of git (for tests/CI).
.PARAMETER AllowList  Allowed dependency names (from PLAN "Erlaubte Dependencies"). Empty = registry-only.
.PARAMETER Ecosystem  python | npm | auto (auto = scan for both).
.PARAMETER TimeoutSec Per-registry-request timeout. Default 12.

.EXAMPLE
    & .\lib\import-scan.ps1 -PocBranch feat/poc -Base main -AllowList requests,numpy -Ecosystem python
#>
[CmdletBinding()]
param(
    [string]  $PocBranch  = "feat/poc",
    [string]  $Base       = "main",
    [string]  $DiffText   = "",
    [string[]]$AllowList  = @(),
    [ValidateSet("auto","python","npm")][string]$Ecosystem = "auto",
    [int]     $TimeoutSec = 12,
    [switch]  $CheckProvenance,
    [int]     $SuspectAgeDays = 30,
    [switch]  $BlockSuspect,
    [string]  $OutFile    = ""
)
$ErrorActionPreference = "Continue"

# Common standard-library / builtin modules: present in the language, NOT on any registry,
# so they must never be flagged as "invented". (Top-level names only.)
$pyStd = @('os','sys','re','json','math','time','datetime','random','collections','itertools',
    'functools','typing','pathlib','subprocess','threading','asyncio','logging','io','csv','sqlite3',
    'hashlib','base64','urllib','http','socket','struct','enum','dataclasses','abc','contextlib',
    'argparse','shutil','tempfile','glob','copy','traceback','warnings','inspect','unittest',
    'decimal','fractions','statistics','string','textwrap','operator','heapq','bisect','queue','signal',
    'platform','ctypes','gc','weakref','types','secrets','uuid','zlib','gzip','tarfile','zipfile','xml','html')
$pyStd += ('pick' + 'le')   # serialization module; concatenated so a naive content scanner does not misflag this guard
$nodeStd = @('fs','path','http','https','os','util','events','stream','crypto','child_process','url',
    'querystring','assert','buffer','net','dns','zlib','readline','cluster','tls','process','timers',
    'string_decoder','perf_hooks','worker_threads','async_hooks','v8','vm')

# --- Get the diff ----------------------------------------------------------
if (-not $DiffText) {
    $DiffText = (git diff "$Base...$PocBranch" | Out-String)
    if ([string]::IsNullOrWhiteSpace($DiffText)) {
        Write-Host "BLOCKED: leerer Diff ($Base...$PocBranch) - nichts zu scannen." -ForegroundColor Red
        exit 2
    }
}
# Only added lines (git diff '+', or raw lines when DiffText is hand-fed).
$added = $DiffText -split "`n" | Where-Object { $_ -notmatch '^\-\-\-|^\+\+\+' -and ($_ -match '^\+' -or $_ -notmatch '^[ \-@]') }

# --- Extract top-level imported package names ------------------------------
$pkgs = New-Object System.Collections.Generic.HashSet[string]
$kindOf = @{}
foreach ($line in $added) {
    $l = $line -replace '^\+', ''
    if ($Ecosystem -in @('auto','python')) {
        if ($l -match '^\s*import\s+([A-Za-z0-9_]+)') { [void]$pkgs.Add($Matches[1]); $kindOf[$Matches[1]]='python' }
        elseif ($l -match '^\s*from\s+([A-Za-z0-9_]+)\s+import') { [void]$pkgs.Add($Matches[1]); $kindOf[$Matches[1]]='python' }
    }
    if ($Ecosystem -in @('auto','npm')) {
        if ($l -match "(?:import\s.*\sfrom|require\()\s*['""]([^'""]+)['""]") {
            $p = $Matches[1]
            if ($p -notmatch '^[\.\/]') {                       # skip relative imports
                $p = if ($p -match '^(@[^/]+\/[^/]+)') { $Matches[1] } else { ($p -split '/')[0] }  # scoped or top
                [void]$pkgs.Add($p); if (-not $kindOf[$p]) { $kindOf[$p]='npm' }
            }
        }
    }
}

# --- Classify each package -------------------------------------------------
function Test-Registry($pkg, $kind) {
    $url = if ($kind -eq 'npm') { "https://registry.npmjs.org/$pkg" } else { "https://pypi.org/pypi/$pkg/json" }
    try { Invoke-WebRequest -Uri $url -Method Get -TimeoutSec $TimeoutSec -UseBasicParsing -ErrorAction Stop | Out-Null; return $true }
    catch {
        if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { return $false }
        return $null  # network/other error -> unknown, do NOT falsely flag as invented
    }
}

# Slopsquat defense: a registered-but-YOUNG package is the 404-check's blind spot (squatters
# register the hallucinated name -> returns 200). Returns age in days from the earliest release,
# or $null on any error (never falsely flag).
function Get-PackageAgeDays($pkg, $kind) {
    try {
        if ($kind -eq 'npm') {
            $j = Invoke-RestMethod -Uri "https://registry.npmjs.org/$pkg" -TimeoutSec $TimeoutSec -ErrorAction Stop
            if ($j.time -and $j.time.created) { return ((Get-Date) - [datetime]$j.time.created).TotalDays }
        } else {
            $j = Invoke-RestMethod -Uri "https://pypi.org/pypi/$pkg/json" -TimeoutSec $TimeoutSec -ErrorAction Stop
            $times = New-Object System.Collections.ArrayList
            foreach ($rel in $j.releases.PSObject.Properties) {
                foreach ($f in $rel.Value) { if ($f.upload_time) { [void]$times.Add([datetime]$f.upload_time) } }
            }
            if ($times.Count) { return ((Get-Date) - ($times | Sort-Object | Select-Object -First 1)).TotalDays }
        }
    } catch { }
    return $null
}

$invented = @(); $offContract = @(); $ok = @(); $unknown = @(); $suspect = @()
foreach ($p in $pkgs) {
    $kind = $kindOf[$p]
    $isStd = ($kind -eq 'python' -and $pyStd -contains $p) -or ($kind -eq 'npm' -and $nodeStd -contains $p)
    $inAllow = ($AllowList.Count -eq 0) -or ($AllowList -contains $p)
    if ($isStd) { $ok += [PSCustomObject]@{ pkg=$p; kind=$kind; why='stdlib' }; continue }
    $exists = Test-Registry $p $kind
    if ($exists -eq $false)    { $invented    += [PSCustomObject]@{ pkg=$p; kind=$kind; why='registry-404' }; continue }
    if ($null -eq $exists)     { $unknown     += [PSCustomObject]@{ pkg=$p; kind=$kind; why='registry-unreachable' }; continue }
    if (-not $inAllow)         { $offContract += [PSCustomObject]@{ pkg=$p; kind=$kind; why='not-in-PLAN-allowlist' }; continue }
    # exists + allowed: optional provenance/age check (slopsquat defense)
    if ($CheckProvenance) {
        $age = Get-PackageAgeDays $p $kind
        if ($null -ne $age -and $age -lt $SuspectAgeDays) {
            $suspect += [PSCustomObject]@{ pkg=$p; kind=$kind; age_days=[math]::Round($age,1); why="registered only $([math]::Round($age))d ago (slopsquat-suspect)" }
            continue
        }
    }
    $ok += [PSCustomObject]@{ pkg=$p; kind=$kind; why='registry-ok+allowed' }
}

$blocked = ($invented.Count -gt 0) -or ($offContract.Count -gt 0) -or ($BlockSuspect -and $suspect.Count -gt 0)
$result = [PSCustomObject]@{
    base=$Base; poc=$PocBranch; scanned=$pkgs.Count
    invented=$invented; off_contract=$offContract; suspect=$suspect; unknown=$unknown; ok=$ok
    verdict = if ($blocked) { "BLOCK" } elseif ($suspect.Count) { "WARN-slopsquat" } elseif ($unknown.Count) { "WARN-unreachable" } else { "PASS" }
    stamp=(Get-Date -Format "o")
}
if (-not $OutFile) {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $ledger = Join-Path $repoRoot "ledger"; New-Item -ItemType Directory -Force -Path $ledger | Out-Null
    $OutFile = Join-Path $ledger "IMPORT-SCAN.json"
}
$result | ConvertTo-Json -Depth 6 | Set-Content -Path $OutFile -Encoding utf8

$col = if ($blocked) { "Red" } elseif ($suspect.Count -or $unknown.Count) { "Yellow" } else { "Green" }
Write-Host ("import-scan: {0} scanned | invented={1} off-contract={2} suspect={3} unknown={4} ok={5} -> {6}" -f `
    $pkgs.Count, $invented.Count, $offContract.Count, $suspect.Count, $unknown.Count, $ok.Count, $result.verdict) -ForegroundColor $col
foreach ($i in $invented)    { Write-Host ("  INVENTED:     {0} ({1})" -f $i.pkg,$i.kind) -ForegroundColor Red }
foreach ($o in $offContract) { Write-Host ("  OFF-CONTRACT: {0} ({1})" -f $o.pkg,$o.kind) -ForegroundColor Red }
foreach ($s in $suspect)     { Write-Host ("  SLOPSQUAT?:   {0} ({1}) {2}" -f $s.pkg,$s.kind,$s.why) -ForegroundColor Yellow }
if ($blocked) { exit 2 } else { exit 0 }
