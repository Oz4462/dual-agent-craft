<#
.SYNOPSIS
    Rechte Split-Screen-Pane: tailt NUR NEUE Grok-Builds live.
.DESCRIPTION
    Beim Start werden vorhandene grok-*.log als Baseline gemerkt und die Pane geleert,
    damit sie FREI startet. Danach erscheint live nur, was ein NEUER dual-build.ps1-Lauf
    schreibt (eigener Poll-Tail, wechselt automatisch auf jeden neuen Build).
#>
$ErrorActionPreference = "Continue"
$logDir = Join-Path $PSScriptRoot ".dual-agent\logs"
$Host.UI.RawUI.WindowTitle = "Grok Live-Log"
try { Clear-Host } catch { }
Write-Host "=== GROK LIVE-LOG ===" -ForegroundColor Cyan
Write-Host "Bereit. Zeigt NUR neue Grok-Builds (ab jetzt). Strg+C zum Beenden.`n" -ForegroundColor DarkGray

# Baseline: bereits vorhandene Logs ignorieren -> Pane startet frei.
$baseline = @{}
Get-ChildItem (Join-Path $logDir "grok-*.log") -ErrorAction SilentlyContinue |
    ForEach-Object { $baseline[$_.FullName] = $true }

$cur = $null
$pos = 0
$waited = $false
while ($true) {
    $log = Get-ChildItem (Join-Path $logDir "grok-*.log") -ErrorAction SilentlyContinue |
           Where-Object { -not $baseline.ContainsKey($_.FullName) } |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($log) {
        if ($log.FullName -ne $cur) {
            $cur = $log.FullName; $pos = 0; $waited = $false
            Write-Host "`n--- neuer Build: $($log.Name) ---" -ForegroundColor Yellow
        }
        try {
            $fs = [System.IO.File]::Open($cur, 'Open', 'Read', 'ReadWrite')
            [void]$fs.Seek($pos, 'Begin')
            $sr = New-Object System.IO.StreamReader($fs)
            $chunk = $sr.ReadToEnd()
            if ($chunk) { Write-Host -NoNewline $chunk }
            $pos = $fs.Position
            $sr.Close(); $fs.Close()
        } catch { }
    } elseif (-not $waited) {
        Write-Host "Warte auf naechsten Grok-Build (dual-build.ps1) ..." -ForegroundColor DarkGray
        $waited = $true
    }
    Start-Sleep -Milliseconds 800
}
