# Plugin config errors must `return', not `exit'.
#
# Covers commit 1747969 ("Avoid exiting the shell on plugin config
# errors"). Three error paths -- (a) the `is-at-least 4.3.11' check at
# the top of the file, (b) a bare-filename ZSHZ_DATA, (c) ZSHZ_DATA
# pointing at a directory -- must all surface their error message and
# bail without taking the user's interactive shell down with them.
#
# `test_datafile.zsh' already covers (b) and (c) by checking that
# `zshz -l && print SENTINEL' doesn't print SENTINEL -- but that
# assertion can't distinguish "zshz returned non-zero" from "the whole
# shell exited," because both produce the same observable. The tests
# below probe the stronger property: a sentinel placed *after* the
# failing call must still print, which only happens if the calling
# shell stayed alive.

# Same self-locator used in test_emulate.zsh / test_strict_options.zsh.
_zshz_test_zsh_bin() {
  local bin
  bin=$(readlink /proc/$$/exe 2>/dev/null)
  [[ -x $bin ]] && { print -- $bin; return }
  print -- ${commands[zsh]:-zsh}
}

test_old_zsh_version_check_returns_does_not_exit() {
  # Shim `is-at-least' to return false, so the version-check branch
  # fires. `autoload' is also shimmed to a no-op so the plugin's
  # `autoload -Uz is-at-least' line doesn't replace our shim with an
  # autoload stub before the check runs. The plugin's
  # `return 1 2>/dev/null || exit 1' should hit the `return' branch
  # (we're being sourced) and the calling shell must continue past
  # the source.
  local zsh_bin out
  zsh_bin=$(_zshz_test_zsh_bin)

  out=$("$zsh_bin" --no-rcs -c "
    autoload() { : }
    is-at-least() { return 1 }
    source '$PLUGIN_DIR/zsh-z.plugin.zsh'
    print POST_SOURCE_SENTINEL
  " 2>&1)

  assert_contains "Zsh-z requires" "$out" \
    "version-check failure should print the user-facing error"
  assert_contains "POST_SOURCE_SENTINEL" "$out" \
    "calling shell should survive a version-check failure"
}

test_bare_ZSHZ_DATA_returns_does_not_exit() {
  # ZSHZ_DATA without a directory component must fail zshz cleanly,
  # leaving the calling shell intact.
  local zsh_bin out
  zsh_bin=$(_zshz_test_zsh_bin)

  out=$("$zsh_bin" --no-rcs -c "
    source '$PLUGIN_DIR/zsh-z.plugin.zsh'
    ZSHZ_DATA=barefile zshz -l
    print POST_BARE_SENTINEL
  " 2>&1)

  assert_contains "barefile" "$out" \
    "bare-filename ZSHZ_DATA should produce the user-facing error"
  assert_contains "POST_BARE_SENTINEL" "$out" \
    "calling shell should survive a bare-filename ZSHZ_DATA"
}

test_directory_ZSHZ_DATA_returns_does_not_exit() {
  # ZSHZ_DATA pointing at a directory must fail zshz cleanly, leaving
  # the calling shell intact.
  local zsh_bin out
  zsh_bin=$(_zshz_test_zsh_bin)
  mkdir -p "$TESTDIR/data-dir"

  out=$("$zsh_bin" --no-rcs -c "
    source '$PLUGIN_DIR/zsh-z.plugin.zsh'
    ZSHZ_DATA='$TESTDIR/data-dir' zshz -l
    print POST_DIR_SENTINEL
  " 2>&1)

  assert_contains "is a directory" "$out" \
    "directory ZSHZ_DATA should produce the user-facing error"
  assert_contains "POST_DIR_SENTINEL" "$out" \
    "calling shell should survive a directory ZSHZ_DATA"
}
# vim: fdm=indent:ts=2:et:sts=2:sw=2:
