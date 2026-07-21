#!/usr/bin/env bash
# install.sh — install the Main Harness into ~/.claude (Claude Code) and mirror
# the builder contract for Grok/Codex (AGENTS.md is read natively by both).
#
# Conservative by design:
#   - DRY-RUN by default: shows exactly what would change.
#   - HARNESS_INSTALL_CONFIRM=1 ./install.sh   actually installs.
#   - settings.json is MERGED via python with a timestamped backup — never blindly
#     overwritten; deny/ask/allow lists and hooks are added, existing keys kept.
set -uo pipefail
export LC_ALL=C
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
TARGET="$CLAUDE_DIR/harness"
CONFIRM="${HARNESS_INSTALL_CONFIRM:-0}"

say() { printf '%s\n' "$*"; }
doit() { if [[ "$CONFIRM" == 1 ]]; then "$@"; else say "  [dry-run] $*"; fi }

say "== Main Harness install =="
say "source : $HERE"
say "target : $TARGET"
say "mode   : $([[ "$CONFIRM" == 1 ]] && echo INSTALL || echo 'DRY-RUN (set HARNESS_INSTALL_CONFIRM=1 to apply)')"
say ""

# 1. Harness payload -> ~/.claude/harness (docs, hooks, prompts, teams, bin)
doit mkdir -p "$TARGET"
for d in operations skills teams workflows automations prompts bin; do
  doit cp -r "$HERE/$d" "$TARGET/"
done
for f in CONTRACT.md REFLEXES.md MUSCLE-MEMORY.md PATTERNS.md; do
  doit cp "$HERE/$f" "$TARGET/"
done

# 2. Skills -> ~/.claude/skills/<name> (Claude Code discovers SKILL.md there)
doit mkdir -p "$CLAUDE_DIR/skills"
for s in "$HERE"/skills/*/; do
  name="$(basename "$s")"
  doit cp -r "$s" "$CLAUDE_DIR/skills/$name"
done

# 3. settings.json merge (permissions + hooks), with backup
merge_settings() {
  local settings="$CLAUDE_DIR/settings.json"
  local stamp; stamp="$(date -u +%Y%m%d-%H%M%S)"
  [[ -f "$settings" ]] && cp "$settings" "$settings.bak-$stamp" && say "backup: $settings.bak-$stamp"
  HOOKS_DIR="$TARGET/operations/hooks" \
  python3 - "$settings" "$HERE/operations/permissions.json" "$HERE/operations/hooks.json" <<'PY'
import sys, json, os
settings_path, perm_path, hooks_path = sys.argv[1:4]
hooks_dir = os.environ["HOOKS_DIR"]
try:
    cur = json.load(open(settings_path, encoding="utf-8"))
except Exception:
    cur = {}
perms = json.load(open(perm_path, encoding="utf-8"))["permissions"]
hooks = json.loads(open(hooks_path, encoding="utf-8").read().replace("__HOOKS_DIR__", hooks_dir))["hooks"]
# merge permissions: union lists, existing entries kept, deny wins by Claude's own precedence
p = cur.setdefault("permissions", {})
for k in ("deny", "ask", "allow"):
    have = p.get(k, [])
    p[k] = have + [x for x in perms.get(k, []) if x not in have]
# merge hooks: append our matchers if an identical command is not already wired
h = cur.setdefault("hooks", {})
for event, entries in hooks.items():
    have = h.setdefault(event, [])
    wired = {hk.get("command") for e in have for hk in e.get("hooks", [])}
    for e in entries:
        if all(hk.get("command") in wired for hk in e.get("hooks", [])):
            continue
        have.append(e)
json.dump(cur, open(settings_path, "w", encoding="utf-8"), indent=2)
print(f"merged -> {settings_path}")
PY
}
if [[ "$CONFIRM" == 1 ]]; then merge_settings; else say "  [dry-run] merge permissions+hooks into $CLAUDE_DIR/settings.json (with backup)"; fi

# 4. Grok/Codex mirror: AGENTS.md already carries the builder contract in-repo.
say ""
say "Grok/Codex: vendor-neutral contract stays in-repo (AGENTS.md — read natively)."
say "Teams     : claude --agents \"\$(cat $TARGET/teams/agents.json)\" --forward-subagent-text"
say ""
if [[ "$CONFIRM" == 1 ]]; then
  # smoke: hooks must be executable + syntax-clean where they now live
  fails=0
  for hk in "$TARGET"/operations/hooks/*.sh; do
    bash -n "$hk" || fails=$((fails+1))
    [[ -x "$hk" ]] || chmod +x "$hk"
  done
  [[ $fails -eq 0 ]] && say "install OK — hooks syntax-clean + executable." || { say "install FAILED: $fails hook(s) broken"; exit 1; }
else
  say "Nothing changed (dry-run)."
fi
