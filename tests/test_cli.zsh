# Help and invalid-option handling.

test_help_short_prints_usage() {
  local out rc
  out=$(zshz -h 2>&1)
  rc=$?

  assert_eq "0" "$rc" "-h should succeed"
  assert_contains "Usage: z" "$out" "-h should print usage"
  assert_contains "--add Add a directory to the database" "$out" "-h should include option help"
}

test_help_long_prints_usage() {
  local out rc
  out=$(zshz --help 2>&1)
  rc=$?

  assert_eq "0" "$rc" "--help should succeed"
  assert_contains "Usage: z" "$out" "--help should print usage"
  assert_contains "-xR   Remove a directory and its subdirectories" "$out" "--help should include detailed options"
}

test_invalid_option_prints_error_and_usage() {
  local out rc
  out=$(zshz -q 2>&1)
  rc=$?

  assert_ne "0" "$rc" "invalid option should fail"
  assert_contains "Improper option(s) given." "$out" "invalid option should print an error"
  assert_contains "Usage: z" "$out" "invalid option should also print usage"
}
