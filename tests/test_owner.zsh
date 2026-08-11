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
  (( ZSHZ[USE_FLOCK] )) || {
    _test_skip "zsystem flock unavailable"
    return 0
  }

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

test_owner_set_chowns_lockfile_at_creation() {
  # The owner handoff must happen when the lockfile is *created*, not only
  # after a successful write -- otherwise a timed-out or failed first write by
  # root under `sudo -s' leaves a root-owned lockfile that makes every later
  # unprivileged --add / -x a silently-swallowed EACCES no-op. The creation
  # handoff logs a chown of the lockfile ALONE, distinct from the post-write
  # chown that covers both files together.
  (( ZSHZ[USE_FLOCK] )) || {
    _test_skip "zsystem flock unavailable"
    return 0
  }

  local chown_log="$TESTDIR/chown.log"
  : > "$chown_log"

  ZSHZ[CHOWN]=_test_log_chown
  _test_log_chown() { print -- "$@" >> "$chown_log"; }

  rm -f "${ZSHZ_DATA}.lock"
  local sub="$TESTDIR/sub"
  mkdir -p "$sub"
  ZSHZ_OWNER=$(id -un) zshz --add "$sub"

  local -a logged
  logged=( ${(f)"$(< $chown_log)"} )
  local l found=0
  for l in $logged; do
    # A standalone lockfile chown: ends with the lockfile and does not also
    # carry the datafile (which the post-write both-files chown would).
    [[ $l == *" ${ZSHZ_DATA}.lock" && $l != *"$ZSHZ_DATA "* ]] && found=1
  done
  assert_eq "1" "$found" \
    "lockfile must be chowned at creation (standalone), not only after a write"
}

test_owner_unset_does_not_chown() {
  (( ZSHZ[USE_FLOCK] )) || {
    _test_skip "zsystem flock unavailable"
    return 0
  }

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
