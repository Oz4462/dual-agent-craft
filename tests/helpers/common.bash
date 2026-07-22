#!/usr/bin/env bash
# tests/helpers/common.bash — shared setup for every .bats file.

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export HARNESS_ROOT

# Fresh scratch dir per test.
setup_scratch() {
  SCRATCH="$(mktemp -d)"
  export SCRATCH
}
teardown_scratch() {
  [[ -n "${SCRATCH:-}" && -d "$SCRATCH" ]] && rm -rf "$SCRATCH"
}

# Make a throwaway git repo with default branch main and an initial commit.
make_repo() {
  local dir="$1"
  git init -q -b main "$dir"
  git -C "$dir" config user.email test@test
  git -C "$dir" config user.name test
  echo base > "$dir/base.txt"
  git -C "$dir" add -A
  git -C "$dir" commit -qm base
}

# Stub registry dir: <pkg>.status files hold HTTP codes, <pkg>.age hold days.
make_registry() {
  REGISTRY="$SCRATCH/registry"
  mkdir -p "$REGISTRY"
  export IMPORT_SCAN_REGISTRY_BASE="file://$REGISTRY"
}

# Install fake vendor CLIs (grok/claude/codex) at the front of PATH.
install_fake_clis() {
  FAKEBIN="$SCRATCH/bin"
  mkdir -p "$FAKEBIN"
  cat > "$FAKEBIN/grok" <<'EOF'
#!/usr/bin/env bash
echo '{"text":"GROK_FAKE_OK","stopReason":"end","sessionId":"s1"}'
echo 'AuthorizationRequired huggingface.co noise' >&2
EOF
  cat > "$FAKEBIN/claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
echo '{"type":"result","result":"CLAUDE_FAKE_OK","is_error":false,"session_id":"abc","total_cost_usd":0.13}'
EOF
  cat > "$FAKEBIN/codex" <<'EOF'
#!/usr/bin/env bash
prev=""
for a in "$@"; do
  [[ "$prev" == "-o" ]] && echo "CODEX_FAKE_OK" > "$a"
  prev="$a"
done
cat >/dev/null
echo '{"type":"item.completed"}'
EOF
  chmod +x "$FAKEBIN"/*
  export PATH="$FAKEBIN:$PATH"
}

# json helper for assertions: jfield <file> <dotted>
jfield() { python3 -c '
import sys, json
obj = json.load(open(sys.argv[1]))
cur = obj
for p in sys.argv[2].split("."):
    cur = cur[p] if isinstance(cur, dict) else cur[int(p)]
print(cur if not isinstance(cur, bool) else str(cur).lower())
' "$1" "$2"; }
