# `ZSHZ[USE_FLOCK]=0` fallback path: when `zsh/system` isn't available,
# `_zshz_add_or_remove_path` skips the lockfile path and writes without flock.
# Single-process add/remove behavior must still hold; concurrent updates can
# race in this mode by design.

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
