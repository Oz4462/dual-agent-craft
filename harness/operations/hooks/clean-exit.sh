#!/usr/bin/env bash
# clean-exit.sh — Stop hook: end-of-session hygiene + shift-note skeleton.
#
# Never blocks the stop (exit 0 always) — it RECORDS instead:
#   - session-end state (branch, dirty files, leftover worktrees) into the
#     tool log, and
#   - appends a pre-filled shift-note skeleton to shift-notes/SHIFT-LOG.md so
#     the cross-session log is never skipped silently (Reflex R9, Muscle #33).
set -uo pipefail
export LC_ALL=C

proj="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$proj" 2>/dev/null || exit 0

stamp="$(date -u +"%Y-%m-%d %H:%M UTC")"
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "no-git")"
dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
worktrees="$(git worktree list 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')"

logdir="$proj/.dual-agent/logs"; mkdir -p "$logdir"
printf '{"stamp":"%s","event":"session-end","branch":"%s","dirty_files":%s,"extra_worktrees":%s}\n' \
  "$stamp" "$branch" "$dirty" "$worktrees" >> "$logdir/TOOL-LOG.jsonl" 2>/dev/null || true

# Shift-note skeleton (only when the harness dir exists in this project).
shiftdir=""
if   [[ -d "$proj/harness/shift-notes" ]]; then shiftdir="$proj/harness/shift-notes"
elif [[ -d "$proj/shift-notes" ]];         then shiftdir="$proj/shift-notes"
fi
if [[ -n "$shiftdir" ]]; then
  {
    printf '\n## %s — session end (auto-skeleton)\n' "$stamp"
    printf -- '- branch: `%s` · dirty files: %s · extra worktrees: %s\n' "$branch" "$dirty" "$worktrees"
    printf -- '- DONE: <fill: what got finished + verified>\n'
    printf -- '- OPEN: <fill: what is half-done, exact next step>\n'
    printf -- '- LESSON: <fill or "none">\n'
  } >> "$shiftdir/SHIFT-LOG.md" 2>/dev/null || true
fi

if [[ "$dirty" != 0 ]]; then
  echo "clean-exit: $dirty uncommitted file(s) on $branch — commit or stash before you forget the context." >&2
fi
exit 0
