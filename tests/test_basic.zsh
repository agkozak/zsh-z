# Smoke tests for the core --add / -x / -l / -e behaviors.

test_add_creates_entry_with_rank_1() {
  zshz --add "$TESTDIR" || return 1
  assert_eq "1" "$(zshz_rank_of "$TESTDIR")" "rank after one add"
}

test_add_same_path_twice_increments_rank() {
  zshz --add "$TESTDIR"
  zshz --add "$TESTDIR"
  assert_eq "2" "$(zshz_rank_of "$TESTDIR")" "rank after two adds"
}

test_add_skips_HOME() {
  zshz --add "$HOME"
  local rank
  rank=$(zshz_rank_of "$HOME")
  assert_eq "" "$rank" "\$HOME should not be added"
}

test_add_skips_excluded_dir() {
  local sub="$TESTDIR/excluded"
  mkdir -p "$sub"
  ZSHZ_EXCLUDE_DIRS=( "$sub" ) zshz --add "$sub"
  assert_eq "" "$(zshz_rank_of "$sub")" "excluded dir should not be added"
}

test_add_skips_subtree_of_excluded_dir() {
  local sub="$TESTDIR/excluded"
  mkdir -p "$sub/child"
  ZSHZ_EXCLUDE_DIRS=( "$sub" ) zshz --add "$sub/child"
  assert_eq "" "$(zshz_rank_of "$sub/child")" "subtree of excluded dir should not be added"
}

test_add_nonexistent_path_returns_nonzero() {
  zshz --add "$TESTDIR/does-not-exist" 2> /dev/null
  local rc=$?
  assert_ne "0" "$rc" "adding a missing path should fail"
}

test_remove_drops_entry() {
  zshz --add "$TESTDIR"
  cd "$TESTDIR"
  zshz -x
  assert_eq "" "$(zshz_rank_of "$TESTDIR")" "entry should be gone after -x"
}

test_remove_R_drops_subtree() {
  local a="$TESTDIR/a" b="$TESTDIR/a/b" c="$TESTDIR/c"
  mkdir -p "$a" "$b" "$c"
  zshz --add "$a"
  zshz --add "$b"
  zshz --add "$c"
  cd "$a"
  zshz -xR
  assert_eq "" "$(zshz_rank_of "$a")" "$a should be removed"
  assert_eq "" "$(zshz_rank_of "$b")" "$b (subtree) should be removed"
  assert_eq "1" "$(zshz_rank_of "$c")" "$c (sibling) should remain"
}

test_list_shows_added_paths() {
  local a="$TESTDIR/alpha" b="$TESTDIR/beta"
  mkdir -p "$a" "$b"
  zshz --add "$a"
  zshz --add "$b"
  local out
  out=$(zshz -l 2>&1)
  assert_contains "$a" "$out" "-l should list $a"
  assert_contains "$b" "$out" "-l should list $b"
}

test_echo_returns_best_match() {
  local a="$TESTDIR/alpha" b="$TESTDIR/alphabet"
  mkdir -p "$a" "$b"
  zshz --add "$a"
  zshz --add "$a"
  zshz --add "$b"
  local out
  out=$(zshz -e alpha 2>&1)
  assert_contains "alpha" "$out" "-e should echo a match for 'alpha'"
}
