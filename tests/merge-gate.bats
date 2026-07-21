#!/usr/bin/env bats
# dual-merge.sh — the 3 No-Cut invariants + graded pass^k gate + test-guard hook.

load helpers/common

setup() {
  setup_scratch
  REPO="$SCRATCH/repo"
  make_repo "$REPO"
  git -C "$REPO" checkout -qb feat/harden
  echo impl > "$REPO/impl.txt"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm impl
  git -C "$REPO" checkout -q main
}
teardown() { teardown_scratch; }

merge() { cd "$REPO" && run "$HARNESS_ROOT/dual-merge.sh" "$@"; }

@test "invariant: disjoint + verify green -> MERGE" {
  merge --from feat/harden --into main --verify "true" --eval-k 3
  [ "$status" -eq 0 ]
  git -C "$REPO" log --oneline main | grep -q impl
}

@test "invariant 4: verify RED -> BLOCK, no merge" {
  merge --from feat/harden --into main --verify "false" --eval-k 3
  [ "$status" -ne 0 ]
  ! git -C "$REPO" log --oneline main | grep -q impl
}

@test "invariant 3: line conflict -> merge ABORTED, never overwritten, clean tree" {
  git -C "$REPO" checkout -qb feat/conf
  echo CONF > "$REPO/base.txt"
  git -C "$REPO" add -A; git -C "$REPO" commit -qm conf
  git -C "$REPO" checkout -q main
  echo MAIN > "$REPO/base.txt"
  git -C "$REPO" add -A; git -C "$REPO" commit -qm mainchange
  merge --from feat/conf --into main --verify "true"
  [ "$status" -ne 0 ]
  [ "$(cat "$REPO/base.txt")" = "MAIN" ]
  [ -z "$(git -C "$REPO" status --porcelain)" ]
}

@test "no --verify and no --force -> BLOCKED" {
  merge --from feat/harden --into main
  [ "$status" -ne 0 ]
  [[ "$output" == *BLOCKED* ]]
}

@test "--force skips verify (explicit override only)" {
  merge --from feat/harden --into main --force
  [ "$status" -eq 0 ]
}

@test "dirty working tree -> BLOCKED before anything happens" {
  echo dirty > "$REPO/dirty.txt"
  merge --from feat/harden --into main --verify "true"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not clean"* ]]
}

@test "graded gate: flaky verify (red then green) -> pass^k=0 -> BLOCK" {
  cat > "$SCRATCH/flaky.sh" <<EOF
#!/usr/bin/env bash
if [[ ! -f "$SCRATCH/ran" ]]; then touch "$SCRATCH/ran"; exit 1; fi
exit 0
EOF
  chmod +x "$SCRATCH/flaky.sh"
  merge --from feat/harden --into main --verify "$SCRATCH/flaky.sh" --eval-k 3
  [ "$status" -ne 0 ]
  ! git -C "$REPO" log --oneline main | grep -q impl
}

@test "--test-guard blocks a merge whose branch edited test files (invariant 7)" {
  git -C "$REPO" checkout -qb feat/cheater
  mkdir -p "$REPO/tests"
  echo 'assert True' > "$REPO/tests/test_gamed.py"
  git -C "$REPO" add -A; git -C "$REPO" commit -qm cheat
  git -C "$REPO" checkout -q main
  merge --from feat/cheater --into main --verify "true" --test-guard
  [ "$status" -ne 0 ]
  ! git -C "$REPO" log --oneline main | grep -q cheat
}

@test "AUDIT-P0: checkout into a branch held by another worktree BLOCKS (no wrong-branch merge)" {
  # hold $INTO (main) in a second linked worktree so `git checkout main` in the
  # primary must fail -> the gate must refuse, never merge into whatever's current.
  held="$SCRATCH/held"
  git -C "$REPO" worktree add -q "$held" main 2>/dev/null || skip "git refused second worktree (version)"
  # move primary off main so main is ONLY in the held worktree
  git -C "$REPO" checkout -q feat/harden
  cd "$REPO"
  run "$HARNESS_ROOT/dual-merge.sh" --from feat/harden --into main --force
  # either it blocks on checkout, or (if this git allows the checkout) it still
  # must not falsely claim success on the wrong branch
  if [ "$status" -eq 0 ]; then
    [ "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)" = "main" ]
  else
    [[ "$output" == *BLOCKED* ]]
  fi
  cd - >/dev/null
}
