# Hook behavior for precmd/chpwd integration.
#
# `_zshz_precmd' backgrounds `zshz --add' via `&!' (fork + disown) so the
# prompt doesn't wait on the read+tempfile+rename+chown round-trip. The
# helper below waits for the disowned write to land before asserting; `wait'
# can't see a `&!'-disowned job, so we poll the datafile.

# Wait up to 2s for $1 to appear in the datafile. Returns 0 once the entry is
# present, 1 on timeout.
_wait_for_add() {
  local target=$1 i
  for ((i=0; i<40; i++)); do
    [[ -n $(zshz_rank_of "$target") ]] && return 0
    sleep 0.05
  done
  return 1
}

# Wait up to 2s for $1 to be absent from the datafile.
_wait_for_remove() {
  local target=$1 i
  for ((i=0; i<40; i++)); do
    [[ -z $(zshz_rank_of "$target") ]] && return 0
    sleep 0.05
  done
  return 1
}

test_precmd_adds_pwd() {
  mkdir -p "$TESTDIR/work"
  cd "$TESTDIR/work"

  _zshz_precmd
  _wait_for_add "$TESTDIR/work"

  assert_eq "1" "$(zshz_rank_of "$TESTDIR/work")" "_zshz_precmd should add PWD"
}

test_precmd_skips_home_and_excluded_dirs() {
  local HOME="$TESTDIR/home"
  mkdir -p "$HOME" "$TESTDIR/excluded/child"
  ZSHZ_EXCLUDE_DIRS=( "$TESTDIR/excluded" )

  cd "$HOME"
  _zshz_precmd
  # No backgrounded write to wait on -- precmd returns before reaching `&!'.
  assert_eq "" "$(zshz_rank_of "$HOME")" "_zshz_precmd should skip HOME"

  cd "$TESTDIR/excluded/child"
  _zshz_precmd
  assert_eq "" "$(zshz_rank_of "$TESTDIR/excluded/child")" "_zshz_precmd should skip excluded subtrees"
}

test_removed_directory_is_not_readded_until_chpwd() {
  mkdir -p "$TESTDIR/work"
  cd "$TESTDIR/work"

  _zshz_precmd
  _wait_for_add "$TESTDIR/work"
  zshz -x "$TESTDIR/work"
  assert_eq "" "$(zshz_rank_of "$TESTDIR/work")" "directory should be removed by -x"

  _zshz_precmd
  # The DIRECTORY_REMOVED guard makes precmd return early, so no add to wait
  # for; sleep briefly to confirm nothing sneaks in late.
  sleep 0.1
  assert_eq "" "$(zshz_rank_of "$TESTDIR/work")" "_zshz_precmd should not immediately re-add a removed directory"

  _zshz_chpwd
  _zshz_precmd
  _wait_for_add "$TESTDIR/work"
  assert_eq "1" "$(zshz_rank_of "$TESTDIR/work")" "_zshz_chpwd should allow later re-addition"
}
# vim: fdm=indent:ts=2:et:sts=2:sw=2:
