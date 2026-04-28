# Listing output and ordering semantics.

test_no_args_matches_list_output() {
  mkdir -p "$TESTDIR/a" "$TESTDIR/b"
  local now=$EPOCHSECONDS
  print -l \
    "$TESTDIR/a|5|$((now - 60))" \
    "$TESTDIR/b|10|$((now - 120))" \
    > "$ZSHZ_DATA"

  assert_eq "$(zshz -l)" "$(zshz)" "calling zshz with no args should behave like -l"
}

test_list_rank_and_time_modes_order_entries() {
  mkdir -p "$TESTDIR/a" "$TESTDIR/b"
  local now=$EPOCHSECONDS
  print -l \
    "$TESTDIR/a|5|$((now - 60))" \
    "$TESTDIR/b|10|$((now - 120))" \
    > "$ZSHZ_DATA"

  local rank_out=$(zshz -lr)
  local -a rank_lines=( ${(f)rank_out} )
  assert_contains "$TESTDIR/a" "$rank_lines[1]" "-lr should list the lower-rank entry first"
  assert_contains "$TESTDIR/b" "$rank_lines[2]" "-lr should list the higher-rank entry second"

  local time_out=$(zshz -lt)
  local -a time_lines=( ${(f)time_out} )
  assert_contains "$TESTDIR/b" "$time_lines[1]" "-lt should list the older entry first"
  assert_contains "$TESTDIR/a" "$time_lines[2]" "-lt should list the newer entry second"
}

test_list_prints_common_root_line() {
  mkdir -p "$TESTDIR/foo" "$TESTDIR/foo/bar"
  local now=$EPOCHSECONDS
  print -l \
    "$TESTDIR/foo|1|$now" \
    "$TESTDIR/foo/bar|2|$now" \
    > "$ZSHZ_DATA"

  local out=$(zshz -l foo)
  local -a lines=( ${(f)out} )
  assert_contains "common:" "$lines[1]" "-l should print a common-root summary when multiple matches share one"
  assert_contains "$TESTDIR/foo" "$lines[1]" "common-root summary should show the shared root"
}
