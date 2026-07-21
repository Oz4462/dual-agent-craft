#!/usr/bin/env bash
# watch-grok.sh — right split-screen pane: tail ONLY NEW Grok builds live.
#
# At start, existing grok-*.err.log/out.json files are baselined so the pane
# starts FREE; then only what a NEW dual-build.sh run writes appears live.
set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
logdir="$_HERE/.dual-agent/logs"
mkdir -p "$logdir"
printf '\033]0;Grok Live-Log\007' 2>/dev/null || true
clear 2>/dev/null || true
printf '=== GROK LIVE-LOG ===\n'
printf 'Ready. Shows ONLY new Grok builds (from now). Ctrl+C to quit.\n\n'

# Baseline: ignore logs that already exist.
declare -A baseline
for f in "$logdir"/grok-*.err.log "$logdir"/grok-*.out.json; do
  [[ -e "$f" ]] && baseline["$f"]=1
done

cur=""; pos=0; waited=false
while true; do
  # newest un-baselined grok log
  log=""
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ -n "${baseline[$f]:-}" ]] && continue
    log="$f"; break
  done < <(ls -t "$logdir"/grok-*.out.json "$logdir"/grok-*.err.log 2>/dev/null)

  if [[ -n "$log" ]]; then
    if [[ "$log" != "$cur" ]]; then
      cur="$log"; pos=0; waited=false
      printf '\n--- new build: %s ---\n' "$(basename "$log")"
    fi
    # Audit fix: a failing stat (file rotated/removed mid-read) must not freeze
    # the pane silently — warn once and re-scan for the next log.
    if ! size=$(stat -c%s "$cur" 2>/dev/null); then
      printf '\n[watch-grok] log vanished (%s) — waiting for the next build ...\n' "$(basename "$cur")" >&2
      baseline["$cur"]=1; cur=""; pos=0
      continue
    fi
    if [[ "$size" -gt "$pos" ]]; then
      if ! dd if="$cur" bs=1 skip="$pos" count=$((size - pos)) 2>/dev/null; then
        printf '\n[watch-grok] read error on %s — retrying ...\n' "$(basename "$cur")" >&2
      fi
      pos=$size
    fi
  elif [[ "$waited" == false ]]; then
    printf 'Waiting for the next Grok build (dual-build.sh) ...\n'
    waited=true
  fi
  sleep 0.8
done
