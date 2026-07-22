#!/usr/bin/env bash
# WP08 verify gate: the pinned acceptance tests (happy path, null cases,
# negative numbers) must exist by name and the suite must pass.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REQUIRED_TESTS=(
  test_happy_path_two_times_three_is_six
  test_null_case_zero_times_five_is_zero
  test_null_case_seven_times_zero_is_zero
  test_null_case_zero_times_zero_is_zero
  test_negative_times_positive_is_negative
  test_negative_times_negative_is_positive
)

for test_name in "${REQUIRED_TESTS[@]}"; do
  if ! grep -q "def ${test_name}(" tests/test_multiply.py; then
    echo "WP08 FAIL: missing pinned test ${test_name}" >&2
    exit 1
  fi
done

python3 -m unittest tests.test_multiply -v
