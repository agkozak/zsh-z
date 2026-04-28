# Hook behavior for precmd/chpwd integration.
#
# These tests force OSTYPE=cygwin so `_zshz_precmd` takes its foreground write
# path; otherwise it backgrounds `zshz --add`, which would make the assertions
# racy.

test_precmd_adds_pwd_in_foreground() {
  mkdir -p "$TESTDIR/work"
  OSTYPE=cygwin
  cd "$TESTDIR/work"

  _zshz_precmd

  assert_eq "1" "$(zshz_rank_of "$TESTDIR/work")" "_zshz_precmd should add PWD"
}

test_precmd_skips_home_and_excluded_dirs() {
  local HOME="$TESTDIR/home"
  mkdir -p "$HOME" "$TESTDIR/excluded/child"
  ZSHZ_EXCLUDE_DIRS=( "$TESTDIR/excluded" )
  OSTYPE=cygwin

  cd "$HOME"
  _zshz_precmd
  assert_eq "" "$(zshz_rank_of "$HOME")" "_zshz_precmd should skip HOME"

  cd "$TESTDIR/excluded/child"
  _zshz_precmd
  assert_eq "" "$(zshz_rank_of "$TESTDIR/excluded/child")" "_zshz_precmd should skip excluded subtrees"
}

test_removed_directory_is_not_readded_until_chpwd() {
  mkdir -p "$TESTDIR/work"
  OSTYPE=cygwin
  cd "$TESTDIR/work"

  _zshz_precmd
  zshz -x "$TESTDIR/work"
  assert_eq "" "$(zshz_rank_of "$TESTDIR/work")" "directory should be removed by -x"

  _zshz_precmd
  assert_eq "" "$(zshz_rank_of "$TESTDIR/work")" "_zshz_precmd should not immediately re-add a removed directory"

  _zshz_chpwd
  _zshz_precmd
  assert_eq "1" "$(zshz_rank_of "$TESTDIR/work")" "_zshz_chpwd should allow later re-addition"
}
