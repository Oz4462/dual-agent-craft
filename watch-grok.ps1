<#
.SYNOPSIS
    Rechte Split-Screen-Pane: tailt Groks Build-Logs LIVE.
.DESCRIPTION
    Pollt .dual-agent/logs/grok-*.log, zeigt das neueste live an und wechselt
    automatisch auf ein neueres Log, sobald dual-build.ps1 einen neuen Lauf startet.
    (Eigener Poll-Tail statt Get-Content -Wait, damit Build-Wechsel erkannt werden.)
#>
$ErrorActionPreference = "Continue"
$logDir = Join-Path $PSScriptRoot ".dual-agent\logs"
$Host.UI.RawUI.WindowTitle = "Grok Live-Log"
Write-Host "=== GROK LIVE-LOG ===" -ForegroundColor Cyan
Write-Host "Wartet auf Grok-Builds (von dual-build.ps1). Strg+C zum Beenden.`n" -ForegroundColor DarkGray

$cur = $null
$pos = 0
while ($true) {
    $log = Get-ChildItem (Join-Path $logDir "grok-*.log") -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($log) {
        if ($log.FullName -ne $cur) {
            $cur = $log.FullName; $pos = 0
            Write-Host "`n--- $($log.Name) ---" -ForegroundColor Yellow
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
    }
    Start-Sleep -Milliseconds 800
}
