# ZSHZ[USE_FLOCK]=0 fallback path: when zsh/system isn't available, Zsh-z
# falls back to a no-flock write (zsh-z.plugin.zsh:227, ~315-321). Single-
# process correctness must still hold; concurrent updates can race in this
# mode, which is fundamental, not a regression.

test_add_works_without_flock() {
  ZSHZ[USE_FLOCK]=0
  zshz --add "$TESTDIR" || return 1
  assert_eq "1" "$(zshz_rank_of "$TESTDIR")" "--add should work without flock"
}

test_remove_works_without_flock() {
  mkdir -p "$TESTDIR/keep" "$TESTDIR/gone"
  ZSHZ[USE_FLOCK]=0
  zshz --add "$TESTDIR/keep"
  zshz --add "$TESTDIR/gone"
  zshz -x "$TESTDIR/gone"
  assert_ne "" "$(zshz_rank_of "$TESTDIR/keep")" "kept entry should remain"
  assert_eq "" "$(zshz_rank_of "$TESTDIR/gone")" "removed entry should be gone"
}

test_no_lockfile_created_without_flock() {
  ZSHZ[USE_FLOCK]=0
  zshz --add "$TESTDIR"
  if [[ -f "${ZSHZ_DATA}.lock" ]]; then
    fail "lockfile should not be created when USE_FLOCK=0"
  fi
}
