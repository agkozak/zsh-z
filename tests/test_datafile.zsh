# Datafile robustness: malformed lines, empty file, missing file.
#
# zsh-z.plugin.zsh:194 filters lines through a glob that requires
# /path|digits[.digits]|digits format. Anything else should be silently
# discarded, not crash zshz or pollute results.

test_malformed_lines_are_filtered() {
  mkdir -p "$TESTDIR/valid"
  cat > "$ZSHZ_DATA" <<EOF
$TESTDIR/valid|5|1700000000

random text
$TESTDIR|nope|123
no-leading-slash|5|1700000000
|5|1700000000
$TESTDIR/missingfields
EOF
  local out
  out=$(zshz -l 2>&1)
  assert_contains "$TESTDIR/valid" "$out" "well-formed entry should be listed"
  assert_not_contains "random text" "$out" "garbage line should not appear"
  assert_not_contains "no-leading-slash" "$out" "non-absolute path should not appear"
  assert_not_contains "missingfields" "$out" "incomplete line should not appear"
}

test_malformed_datafile_does_not_break_add() {
  cat > "$ZSHZ_DATA" <<EOF
total garbage
more garbage
EOF
  zshz --add "$TESTDIR" || return 1
  assert_eq "1" "$(zshz_rank_of "$TESTDIR")" "--add should still work despite malformed prior content"
}

test_empty_datafile() {
  : > "$ZSHZ_DATA"
  zshz --add "$TESTDIR" || return 1
  assert_eq "1" "$(zshz_rank_of "$TESTDIR")" "add to empty datafile should create the entry"
}

test_missing_datafile_is_created() {
  rm -f "$ZSHZ_DATA"
  zshz --add "$TESTDIR" || return 1
  assert_file_exists "$ZSHZ_DATA"
  assert_eq "1" "$(zshz_rank_of "$TESTDIR")" "add when datafile missing should create and populate it"
}

test_ZSHZ_DATA_without_directory_prints_error_and_exits() {
  local out=$(zshz_in_fresh_shell '
    ZSHZ_DATA=barefile zshz -l
    print SENTINEL
  ' 2>&1)

  assert_contains "ERROR: You configured a custom Zsh-z datafile (barefile), but have not specified its directory." "$out" "bare filename should be rejected"
  assert_not_contains "SENTINEL" "$out" "shell should exit before reaching later commands"
}

test_ZSHZ_DATA_directory_prints_error_and_exits() {
  mkdir -p "$TESTDIR/data-dir"
  local out=$(zshz_in_fresh_shell "
    ZSHZ_DATA='$TESTDIR/data-dir' zshz -l
    print SENTINEL
  " 2>&1)

  assert_contains "ERROR: Zsh-z's datafile ($TESTDIR/data-dir) is a directory." "$out" "directory datafile should be rejected"
  assert_not_contains "SENTINEL" "$out" "shell should exit before reaching later commands"
}
