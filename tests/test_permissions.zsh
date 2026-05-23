# Datafile permission hardening (#92).
#
# `~/.z` must always end up at mode 0600 so a multi-user host can't read
# another user's directory history. The plugin enforces this by chmodding
# the file on initial creation and chmodding every tempfile before the
# rename that replaces `.z'. These tests cover all the write paths that
# could leak permissions: fresh creation, `--add' over a preexisting
# 0644 file, `-x' (the remove branch), and the `ZSHZ_OWNER' initial-
# creation chown that hands `.z' off to the right user under `sudo -s'.
#
# MSYS2 deliberately no-ops chmod (Windows filesystems don't honor
# POSIX modes), so the mode-checking tests skip there.

# Octal regular-permission bits of $1 (e.g. "600"). Returns empty if the
# `zsh/stat' module isn't loadable. Uses `8#777' rather than `0777' because
# zsh treats `0777' as decimal 777 without `setopt OCTAL_ZEROES'.
_test_mode_of() {
  zmodload -F zsh/stat b:zstat 2>/dev/null
  (( ${+builtins[zstat]} )) || return
  local m
  m=$(zstat -L +mode "$1") || return
  printf '%03o\n' $(( m & 8#777 ))
}

# Skip mode-checking tests on platforms where chmod is intentionally a
# no-op or where zsh/stat is unavailable. Returns 0 (skip) or 1 (run).
_test_skip_mode_check() {
  [[ $OSTYPE == msys ]] && return 0
  zmodload -F zsh/stat b:zstat 2>/dev/null
  (( ${+builtins[zstat]} )) || return 0
  return 1
}

test_initial_creation_is_0600() {
  _test_skip_mode_check && return 0

  rm -f "$ZSHZ_DATA"
  zshz -l
  assert_file_exists "$ZSHZ_DATA"
  assert_eq "600" "$(_test_mode_of "$ZSHZ_DATA")" \
    "fresh .z must be created at mode 0600"
}

test_add_clamps_preexisting_world_readable_file_to_0600() {
  _test_skip_mode_check && return 0

  : > "$ZSHZ_DATA" && chmod 644 "$ZSHZ_DATA"
  assert_eq "644" "$(_test_mode_of "$ZSHZ_DATA")" "precondition: file is 0644"

  mkdir -p "$TESTDIR/work"
  zshz --add "$TESTDIR/work" || return 1
  assert_eq "600" "$(_test_mode_of "$ZSHZ_DATA")" \
    "--add must clamp a preexisting 0644 .z to 0600 via the tempfile rename"
}

test_remove_keeps_0600() {
  _test_skip_mode_check && return 0

  local d="$TESTDIR/r"
  mkdir -p "$d"
  zshz --add "$d" || return 1
  zshz -x "$d" || return 1
  assert_eq "600" "$(_test_mode_of "$ZSHZ_DATA")" \
    "-x must leave .z at mode 0600 after the rewrite"
}

test_repeated_writes_keep_0600() {
  # Each --add rewrites the datafile via a fresh tempfile. Loosening
  # permissions on any single write would defeat the protection, so
  # walk a handful of writes and assert after each one.
  _test_skip_mode_check && return 0

  local i d
  for i in 1 2 3 4 5; do
    d="$TESTDIR/d$i"
    mkdir -p "$d"
    zshz --add "$d" || return 1
    assert_eq "600" "$(_test_mode_of "$ZSHZ_DATA")" \
      "iteration $i: .z must remain at mode 0600 after every --add"
  done
}

test_initial_creation_chowns_when_ZSHZ_OWNER_set() {
  # Under `sudo -s' with ZSHZ_OWNER=user, a query-only `z foo' would
  # otherwise leave a root-owned .z behind that the normal-user shell
  # can't read. The create path therefore chowns to ZSHZ_OWNER eagerly,
  # without waiting for a write to happen. We can't fabricate two UIDs
  # in CI, so we stub ${ZSHZ[CHOWN]} and assert the call shape.
  local chown_log="$TESTDIR/chown.log"
  : > "$chown_log"

  ZSHZ[CHOWN]=_test_log_chown
  _test_log_chown() { print -- "$@" >> "$chown_log"; }

  rm -f "$ZSHZ_DATA"
  ZSHZ_OWNER=$(id -un) zshz -l

  local logged
  logged=$(< "$chown_log")
  assert_contains "$ZSHZ_DATA" "$logged" \
    "initial creation must chown the datafile when ZSHZ_OWNER is set"
}

test_initial_creation_does_not_chown_when_ZSHZ_OWNER_unset() {
  local chown_log="$TESTDIR/chown.log"
  : > "$chown_log"

  ZSHZ[CHOWN]=_test_log_chown
  _test_log_chown() { print -- "$@" >> "$chown_log"; }

  rm -f "$ZSHZ_DATA"
  unset ZSHZ_OWNER _Z_OWNER
  zshz -l

  assert_eq "" "$(< "$chown_log")" \
    "no chown should fire on initial creation when ZSHZ_OWNER is unset"
}
# vim: fdm=indent:ts=2:et:sts=2:sw=2:
