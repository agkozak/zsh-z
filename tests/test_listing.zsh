# Listing output and ordering semantics.

test_no_args_matches_list_output() {
  mkdir -p "$TESTDIR/a" "$TESTDIR/b"
  zshz_seed "$TESTDIR/a" 5 60
  zshz_seed "$TESTDIR/b" 10 120

  # Each invocation caches its own $EPOCHSECONDS, so if the clock ticks
  # between the two captures every frecency rank drifts by one part in
  # ~10^4 and the byte comparison fails -- seen on Cygwin CI, where the
  # two command-substitution forks are slow. Retry only when a tick
  # landed inside the capture window; a genuine behavioral difference
  # fails on every attempt.
  local list no_args before
  integer attempt
  for attempt in 1 2 3; do
    before=$EPOCHSECONDS
    list=$(zshz -l)
    no_args=$(zshz)
    [[ $list == "$no_args" || $EPOCHSECONDS == $before ]] && break
  done
  assert_eq "$list" "$no_args" "calling zshz with no args should behave like -l"
}

test_list_rank_and_time_modes_order_entries() {
  mkdir -p "$TESTDIR/a" "$TESTDIR/b"
  zshz_seed "$TESTDIR/a" 5 60
  zshz_seed "$TESTDIR/b" 10 120

  local rank_out
  local -a rank_lines
  rank_out=$(zshz -lr)
  rank_lines=( ${(f)rank_out} )
  assert_contains "$TESTDIR/a" "$rank_lines[1]" "-lr should list the lower-rank entry first"
  assert_contains "$TESTDIR/b" "$rank_lines[2]" "-lr should list the higher-rank entry second"

  local time_out
  local -a time_lines
  time_out=$(zshz -lt)
  time_lines=( ${(f)time_out} )
  assert_contains "$TESTDIR/b" "$time_lines[1]" "-lt should list the older entry first"
  assert_contains "$TESTDIR/a" "$time_lines[2]" "-lt should list the newer entry second"
}

test_list_prints_common_root_line() {
  mkdir -p "$TESTDIR/foo" "$TESTDIR/foo/bar"
  zshz_seed "$TESTDIR/foo" 1
  zshz_seed "$TESTDIR/foo/bar" 2

  local out
  local -a lines
  out=$(zshz -l foo)
  lines=( ${(f)out} )
  assert_contains "common:" "$lines[1]" "-l should print a common-root summary when multiple matches share one"
  assert_contains "$TESTDIR/foo" "$lines[1]" "common-root summary should show the shared root"
}
test_list_with_query_does_not_change_directory() {
  mkdir -p "$TESTDIR/proj/sub" "$TESTDIR/lone"
  zshz_seed "$TESTDIR/proj" 10
  zshz_seed "$TESTDIR/proj/sub" 5
  zshz_seed "$TESTDIR/lone" 3

  # Run -l in the current shell, not inside a `$( )' capture: the regression
  # this guards against (a REPLY value leaking out of _zshz_output into the
  # jump block) moves the calling shell, and a command substitution subshell
  # can never observe that.
  cd "$TESTDIR"
  local before=$PWD

  # Multiple matches sharing a common root
  zshz -l proj > /dev/null
  assert_eq "$before" "$PWD" "-l with a query must not change directory when matches share a common root"

  # A single match -- its own common root, the everyday trigger
  zshz -l lone > /dev/null
  assert_eq "$before" "$PWD" "-l with a single match must not change directory"
}
# vim: fdm=indent:ts=2:et:sts=2:sw=2:
