#!/usr/bin/env bats
# dual-build.sh — Render-phase orchestration with a configurable fake grok.
# Protects the audit fixes (worktree path, deny wiring, honest exit, junk strip).

load helpers/common

setup() {
  setup_scratch
  REPO="$SCRATCH/repo"
  make_repo "$REPO"
  # a real (non-template) contract
  printf '# PLAN\n## Problem\nbuild a thing.\n' > "$REPO/PLAN.md"
  git -C "$REPO" add -A; git -C "$REPO" commit -qm plan
  FAKEBIN="$SCRATCH/bin"; mkdir -p "$FAKEBIN"; export PATH="$FAKEBIN:$PATH"
}
teardown() {
  # remove any wt-* the render created next to the repo
  rm -rf "$SCRATCH"/wt-* 2>/dev/null || true
  teardown_scratch
}

# fake grok that records its argv and creates a POC file; exit code configurable.
mk_grok() {
  local rc="${1:-0}"
  cat > "$FAKEBIN/grok" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$SCRATCH/grok.argv"
# find --cwd and drop a src file there (simulate a build)
prev=""; cwd=""
for a in "\$@"; do [ "\$prev" = "--cwd" ] && cwd="\$a"; prev="\$a"; done
[ -n "\$cwd" ] && { mkdir -p "\$cwd/src"; echo "print('ok')" > "\$cwd/src/app.py"; }
echo '{"text":"built"}'
exit $rc
EOF
  chmod +x "$FAKEBIN/grok"
}

@test "AUDIT: unfilled PLAN.template.md is BLOCKED, no render" {
  cp "$HARNESS_ROOT/PLAN.template.md" "$REPO/PLAN.md"
  git -C "$REPO" add -A; git -C "$REPO" commit -qm tmpl
  mk_grok 0
  cd "$REPO"
  run "$HARNESS_ROOT/dual-build.sh" --variants 1
  [ "$status" -ne 0 ]
  [[ "$output" == *BLOCKED* ]]
  [ ! -f "$SCRATCH/grok.argv" ]   # grok never called
  cd - >/dev/null
}

@test "AUDIT: render exit 0 -> script exit 0, POC committed on feat/poc, no INCOMPLETE label" {
  mk_grok 0
  cd "$REPO"
  run "$HARNESS_ROOT/dual-build.sh" --variants 1
  [ "$status" -eq 0 ]
  git -C "$REPO" rev-parse --verify feat/poc >/dev/null
  git -C "$REPO" log -1 --format=%s feat/poc | grep -q '^poc:'
  ! git -C "$REPO" log -1 --format=%s feat/poc | grep -qi INCOMPLETE
  cd - >/dev/null
}

@test "AUDIT: render exit != 0 -> script propagates non-zero exit, POC labeled INCOMPLETE" {
  mk_grok 1
  cd "$REPO"
  run "$HARNESS_ROOT/dual-build.sh" --variants 1
  [ "$status" -ne 0 ]
  git -C "$REPO" log -1 --format=%s feat/poc | grep -qi INCOMPLETE
  cd - >/dev/null
}

@test "AUDIT-P1(#6): grok is invoked with the least-privilege --deny rules + --always-approve" {
  mk_grok 0
  cd "$REPO"
  run "$HARNESS_ROOT/dual-build.sh" --variants 1
  [ "$status" -eq 0 ]
  grep -q -- '--always-approve' "$SCRATCH/grok.argv"
  grep -q -- '--deny' "$SCRATCH/grok.argv"
  grep -q 'Bash(git push \*)' "$SCRATCH/grok.argv"
  grep -q 'Bash(rm -rf \*)' "$SCRATCH/grok.argv"
  cd - >/dev/null
}

@test "AUDIT: worktree is a sibling of the repo TOPLEVEL, not nested inside it" {
  mk_grok 0
  mkdir -p "$REPO/sub"
  cd "$REPO/sub"                       # run from a subdir (--plan absolute)
  run "$HARNESS_ROOT/dual-build.sh" --variants 1 --plan "$REPO/PLAN.md"
  [ "$status" -eq 0 ]
  # no wt-* checkout was created INSIDE the repo (toplevel-sibling, not cwd-nested)
  [ ! -d "$REPO/wt-feat-poc" ]
  [ ! -d "$REPO/sub/wt-feat-poc" ]
  cd - >/dev/null
}
