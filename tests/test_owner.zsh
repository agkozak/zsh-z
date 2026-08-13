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

# The tests below cover the symlink hardening. In the documented `sudo -s'
# setup every chown runs with root's authority over paths inside a home
# directory the unprivileged owner controls, and `chown' dereferences by
# default -- so a symlink planted at $datafile or ${datafile}.lock would
# redirect it onto an arbitrary file. We can't fabricate a second UID here, so
# these assert the two defenses directly: `-h' on every chown, and an outright
# refusal to act on a symlinked path while an owner is set.

test_owner_chown_never_dereferences_symlinks() {
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

  local -a logged
  logged=( ${(f)"$(< $chown_log)"} )
  assert_ne "0" "${#logged}" "expected at least one chown to be logged"

  # `-h' is a no-op on the regular files this normally sees; it matters only
  # when the path has been replaced by a symlink since the last check.
  local l bad=0
  for l in $logged; do
    [[ $l == '-h '* ]] || bad=1
  done
  assert_eq "0" "$bad" \
    "every chown must pass -h so a planted symlink is retitled, not followed"
}

test_owner_refuses_symlinked_lockfile() {
  # The lockfile is deliberately never removed, so unlike $datafile -- which
  # the `mv' replaces outright -- a symlink planted here would survive and be
  # acted on at every subsequent write.
  (( ZSHZ[USE_FLOCK] )) || {
    _test_skip "zsystem flock unavailable"
    return 0
  }
  _test_skip_no_symlinks && { print "skip: filesystem has no resolvable symlinks"; return 0 }

  local decoy="$TESTDIR/decoy"
  print 'untouched' > "$decoy"

  local sub="$TESTDIR/sub" sub2="$TESTDIR/sub2"
  mkdir -p "$sub" "$sub2"
  zshz --add "$sub"

  rm -f "${ZSHZ_DATA}.lock"
  ln -s "$decoy" "${ZSHZ_DATA}.lock"

  local ret=0
  ZSHZ_OWNER=$(id -un) zshz --add "$sub2" || ret=$?

  assert_ne "0" "$ret" \
    "a symlinked lockfile must be refused while ZSHZ_OWNER is set"
  assert_eq "untouched" "$(< "$decoy")" \
    "the lockfile symlink's target must not be written through"
  assert_not_contains "$sub2" "$(zshz_dump)" \
    "a refused write must not reach the datafile"
}

test_symlinked_lockfile_allowed_when_owner_unset() {
  # The refusal is gated on $ZSHZ_OWNER on purpose: with no owner set no
  # privilege boundary is crossed, and an unprivileged user pointing their own
  # lockfile elsewhere keeps working exactly as before.
  (( ZSHZ[USE_FLOCK] )) || {
    _test_skip "zsystem flock unavailable"
    return 0
  }
  _test_skip_no_symlinks && { print "skip: filesystem has no resolvable symlinks"; return 0 }

  local elsewhere="$TESTDIR/elsewhere.lock"
  : > "$elsewhere"

  local sub="$TESTDIR/sub" sub2="$TESTDIR/sub2"
  mkdir -p "$sub" "$sub2"
  zshz --add "$sub"

  rm -f "${ZSHZ_DATA}.lock"
  ln -s "$elsewhere" "${ZSHZ_DATA}.lock"

  unset ZSHZ_OWNER _Z_OWNER
  zshz --add "$sub2"

  assert_contains "$sub2" "$(zshz_dump)" \
    "a symlinked lockfile must stay usable when no owner is set"
}

test_symlinked_datafile_is_dereferenced_and_lockfile_follows_it() {
  # A symlinked $ZSHZ_DATA is deliberately dereferenced by `_zshz_realpath'
  # before any of the write machinery sees it, so there is no symlink left for
  # a `-L' guard to catch and no point adding one: $ZSHZ_DATA can already name
  # any path outright, symlink or not. What that resolution does mean is that
  # the lockfile is derived from the *resolved* path -- pinned here because the
  # lockfile's own symlink refusal depends on it being a derived name the user
  # never supplies directly.
  (( ZSHZ[USE_FLOCK] )) || {
    _test_skip "zsystem flock unavailable"
    return 0
  }
  _test_skip_no_symlinks && { print "skip: filesystem has no resolvable symlinks"; return 0 }

  local real="$TESTDIR/real.z"
  : > "$real"
  rm -f "$ZSHZ_DATA"
  ln -s "$real" "$ZSHZ_DATA"

  local sub="$TESTDIR/sub"
  mkdir -p "$sub"
  ZSHZ_OWNER=$(id -un) zshz --add "$sub"

  assert_contains "$sub" "$(< "$real")" \
    "a symlinked datafile must be followed to its target, as documented"
  assert_file_exists "${real}.lock"
  if [[ -e ${ZSHZ_DATA}.lock ]]; then
    fail "the lockfile must sit beside the resolved datafile, not the symlink"
  fi
}
# vim: fdm=indent:ts=2:et:sts=2:sw=2:
