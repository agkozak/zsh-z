# ZSHZ_OWNER / sudo -s ownership behavior.
#
# When ZSHZ_OWNER is set (the documented `sudo -s` workflow), Zsh-z chowns the
# datafile back to that owner after every successful write. The lockfile at
# ${datafile}.lock must get the same treatment: zsystem flock opens it O_RDWR,
# so if root creates it first under sudo and the unprivileged $ZSHZ_OWNER
# user's subsequent flocks fail with EACCES, the error is swallowed by
# `2> /dev/null || return` and --add / -x silently do nothing.
#
# We can't fabricate two real UIDs in CI, so instead we replace ${ZSHZ[CHOWN]}
# with a logger and assert that the chown call covers both files together.

test_owner_set_chowns_both_datafile_and_lockfile() {
  (( ZSHZ[USE_FLOCK] )) || return 0  # No lockfile when flock is unavailable.

  local chown_log="$TESTDIR/chown.log"
  : > "$chown_log"

  ZSHZ[CHOWN]=_test_log_chown
  _test_log_chown() { print -- "$@" >> "$chown_log"; }

  local sub="$TESTDIR/sub"
  mkdir -p "$sub"
  ZSHZ_OWNER=$(id -un) zshz --add "$sub"

  local logged
  logged=$(< "$chown_log")
  assert_contains "$ZSHZ_DATA ${ZSHZ_DATA}.lock" "$logged" \
    "chown must cover datafile and lockfile together when ZSHZ_OWNER is set"
}

test_owner_unset_does_not_chown() {
  (( ZSHZ[USE_FLOCK] )) || return 0

  local chown_log="$TESTDIR/chown.log"
  : > "$chown_log"

  ZSHZ[CHOWN]=_test_log_chown
  _test_log_chown() { print -- "$@" >> "$chown_log"; }

  local sub="$TESTDIR/sub"
  mkdir -p "$sub"
  unset ZSHZ_OWNER _Z_OWNER
  zshz --add "$sub"

  assert_eq "" "$(< "$chown_log")" \
    "no chown should fire when ZSHZ_OWNER is unset"
}
# vim: fdm=indent:ts=2:et:sts=2:sw=2:
