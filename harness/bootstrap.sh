#!/usr/bin/env bash
# bootstrap.sh — online bootstrap for a fresh machine (the VETTED install path).
#
# Deliberately NOT a `curl | bash` one-liner — our own guard blocks that pattern.
# Instead: download → inspect → run, with every step visible:
#
#   curl -fsSLO https://raw.githubusercontent.com/Oz4462/dual-agent-craft/main/harness/bootstrap.sh
#   less bootstrap.sh          # read what you are about to run
#   bash bootstrap.sh          # clones the repo + dry-runs the installer
#
# Idempotent; never touches ~/.claude without HARNESS_INSTALL_CONFIRM=1.
set -uo pipefail
export LC_ALL=C

REPO_URL="${DUAL_AGENT_REPO:-https://github.com/Oz4462/dual-agent-craft.git}"
DEST="${DUAL_AGENT_HOME:-$HOME/dual-agent-craft}"

say() { printf '%s\n' "$*"; }
die() { printf 'BLOCKED: %s\n' "$*" >&2; exit 1; }

say "== dual-agent-craft bootstrap =="

# 1. Preconditions — fail early, with names.
missing=()
for c in git python3 curl bash; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
[[ ${#missing[@]} -gt 0 ]] && die "missing prerequisites: ${missing[*]} (install them first)"
say "prereqs : git python3 curl bash — ok"
for c in claude grok codex tmux ollama; do
  command -v "$c" >/dev/null 2>&1 && say "found   : $c" || say "optional: $c NOT installed"
done

# 2. Clone or update the repo (never destructive: existing dir must be the repo).
if [[ -d "$DEST/.git" ]]; then
  say "repo    : $DEST exists — fetching updates (no checkout changes)"
  git -C "$DEST" fetch --all --quiet || die "fetch failed in $DEST"
elif [[ -e "$DEST" ]]; then
  die "$DEST exists but is not a git repo — refusing to touch it."
else
  say "repo    : cloning -> $DEST"
  git clone --quiet "$REPO_URL" "$DEST" || die "clone failed: $REPO_URL"
fi

# 3. Verify the harness runs HERE (offline suite, deterministic, $0).
say "verify  : running the deterministic suite ..."
if ( cd "$DEST" && tests/run.sh >/dev/null 2>&1 ); then
  say "verify  : suite GREEN"
else
  die "suite RED on this machine — fix before installing (run: cd $DEST && tests/run.sh)"
fi

# 4. Installer dry-run (nothing changes without explicit confirm).
say ""
"$DEST/harness/install.sh"
say ""
say "Next steps:"
say "  cd $DEST"
say "  HARNESS_INSTALL_CONFIRM=1 harness/install.sh    # actually install into ~/.claude"
say "  ./dual-view.sh                                  # split cockpit (needs tmux)"
