<#
.SYNOPSIS
    Split-Screen-Cockpit fuer den Dual-Agent-Workflow (Windows Terminal).
.DESCRIPTION
    Oeffnet Windows Terminal mit zwei Panes nebeneinander:
      links  : Claude Code (Architect/Reviewer) - hier arbeitest du mit Claude.
      rechts : Groks Live-Build-Log (watch-grok.ps1) - du siehst Grok bauen,
               sobald Claude dual-build.ps1 ausloest.
    Mit -Grok startet die rechte Pane stattdessen eine INTERAKTIVE Grok-Session.
.PARAMETER Grok
    Rechte Pane = interaktives `grok` statt Log-Watcher.
.EXAMPLE
    .\dual-view.ps1          # links Claude, rechts Grok-Live-Log
    .\dual-view.ps1 -Grok    # links Claude, rechts interaktiver Grok
#>
param([switch]$Grok)
$ErrorActionPreference = "Continue"
$dir = $PSScriptRoot

if (-not (Get-Command wt -ErrorAction SilentlyContinue)) {
    Write-Host "Windows Terminal (wt) nicht gefunden. Aus dem Store installieren oder Panes manuell oeffnen." -ForegroundColor Red
    exit 1
}

if ($Grok) {
    & wt new-tab -d "$dir" --title Claude powershell -NoExit -NoProfile -Command claude `; `
        split-pane -V -d "$dir" --title Grok powershell -NoExit -NoProfile -Command grok
} else {
    & wt new-tab -d "$dir" --title Claude powershell -NoExit -NoProfile -Command claude `; `
        split-pane -V -d "$dir" --title Grok-Log powershell -NoExit -NoProfile -File "$dir\watch-grok.ps1"
}
Write-Host "Split-View gestartet (links Claude, rechts $(if($Grok){'Grok'}else{'Grok-Live-Log'}))." -ForegroundColor Green
