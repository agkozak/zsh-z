# Stale-entry cleanup and ZSHZ_KEEP_DIRS.
#
# Entries whose paths no longer exist on disk are pruned from the datafile
# on the next write (zsh-z.plugin.zsh:363-377). ZSHZ_KEEP_DIRS shields a
# subtree from that pruning, useful for ephemeral mounts.

test_stale_entry_pruned_on_next_write() {
  mkdir -p "$TESTDIR/keep" "$TESTDIR/gone"
  zshz --add "$TESTDIR/keep"
  zshz --add "$TESTDIR/gone"
  rm -rf "$TESTDIR/gone"

  zshz --add "$TESTDIR/keep"  # forces a write -> triggers prune

  assert_eq "" "$(zshz_rank_of "$TESTDIR/gone")" "missing dir should be pruned"
  assert_ne "" "$(zshz_rank_of "$TESTDIR/keep")" "existing dir should remain"
}

test_keep_dirs_protects_subtree() {
  mkdir -p "$TESTDIR/holdme/x" "$TESTDIR/lose" "$TESTDIR/trigger"
  zshz --add "$TESTDIR/holdme/x"
  zshz --add "$TESTDIR/lose"
  rm -rf "$TESTDIR/holdme" "$TESTDIR/lose"

  ZSHZ_KEEP_DIRS=( "$TESTDIR/holdme" ) zshz --add "$TESTDIR/trigger"

  assert_eq "1" "$(zshz_rank_of "$TESTDIR/holdme/x")" "subtree under KEEP_DIRS should survive"
  assert_eq "" "$(zshz_rank_of "$TESTDIR/lose")" "non-kept missing entry should be pruned"
}

test_keep_dirs_protects_exact_match() {
  mkdir -p "$TESTDIR/exact" "$TESTDIR/trigger"
  zshz --add "$TESTDIR/exact"
  rm -rf "$TESTDIR/exact"

  ZSHZ_KEEP_DIRS=( "$TESTDIR/exact" ) zshz --add "$TESTDIR/trigger"

  assert_eq "1" "$(zshz_rank_of "$TESTDIR/exact")" "exact-match KEEP_DIRS entry should survive"
}
