#!/usr/bin/env bats
# portable.bats — Linux/macOS portability of common helpers (no vendor CLIs).

load helpers/common

setup() { setup_scratch; }
teardown() { teardown_scratch; }

@test "bash is 4+" {
  run bash -c 'echo ${BASH_VERSINFO[0]}'
  [ "$status" -eq 0 ]
  [ "${output}" -ge 4 ]
}

@test "utc_stamp / utc_stamp_ms / iso_now are non-empty and shaped" {
  # shellcheck source=lib/common.sh
  # Call inside same shell — bats `run` is a subshell and would lose sourced fns.
  source "$HARNESS_ROOT/lib/common.sh"
  s=$(utc_stamp)
  ms=$(utc_stamp_ms)
  iso=$(iso_now)
  # format: YYYYMMDD-HHMMSS  and  YYYYMMDD-HHMMSS-mmm
  [[ "$s" =~ ^[0-9]{8}-[0-9]{6}$ ]]
  [[ "$ms" =~ ^[0-9]{8}-[0-9]{6}-[0-9]{3}$ ]]
  [[ "$iso" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "sed_i edits in place on this platform" {
  source "$HARNESS_ROOT/lib/common.sh"
  f="$SCRATCH/t.txt"
  echo "alpha" >"$f"
  sed_i 's/alpha/beta/' "$f"
  [ "$(cat "$f")" = "beta" ]
}

@test "file_size_bytes reports size" {
  source "$HARNESS_ROOT/lib/common.sh"
  f="$SCRATCH/s.bin"
  printf '12345' >"$f"
  n=$(file_size_bytes "$f")
  [ "$n" -eq 5 ]
}

@test "dual_os returns known token" {
  source "$HARNESS_ROOT/lib/common.sh"
  os=$(dual_os)
  [[ "$os" == "linux" || "$os" == "darwin" || "$os" == "windows" || "$os" == "unknown" ]]
}
