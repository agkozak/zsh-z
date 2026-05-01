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

test_complete_does_not_trigger_add_side_effect() {
  # Regression: tab completion of `z --add <dir>` reaches zshz as
  # `zshz --complete --add <dir>`. zparseopts captures both flags, so the
  # for-loop used to also run the --add branch and silently write to the
  # datafile. --complete must stay side-effect-free.
  zshz --complete --add "$TESTDIR" > /dev/null
  assert_eq "" "$(zshz_rank_of "$TESTDIR")" \
    "'--complete --add' must not write to the datafile"
}

test_complete_does_not_trigger_remove_side_effect() {
  zshz --add "$TESTDIR"
  assert_eq "1" "$(zshz_rank_of "$TESTDIR")" "precondition: entry should exist"
  cd "$TESTDIR"
  zshz --complete -x > /dev/null
  assert_eq "1" "$(zshz_rank_of "$TESTDIR")" \
    "'--complete -x' must not remove entries"
}

test_complete_help_combo_is_silent() {
  # --help under --complete must not emit the usage banner; the runner already
  # treats any stderr as a failure, but assert explicitly so the intent is clear.
  local out err
  out=$(zshz --complete --help 2> /dev/null)
  err=$(zshz --complete --help 2>&1 > /dev/null)
  assert_not_contains "Usage: z" "$out" "'--complete --help' must not print usage to stdout"
  assert_not_contains "Usage: z" "$err" "'--complete --help' must not print usage to stderr"
}
# vim: fdm=indent:ts=2:et:sts=2:sw=2:
