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

test_precmd_does_not_emit_done_line_in_interactive_shell() {
  # Verify the user-visible promise of `&!' in `_zshz_precmd': in an
  # interactive shell, the backgrounded `zshz --add' must not produce
  # a "[N]  + done" notification at the next prompt.
  #
  # The function-call boundary of `_zshz_precmd' alone is NOT enough to
  # suppress that line -- with MONITOR on (default in interactive zsh),
  # plain `cmd &' inside a function still surfaces a Done notification
  # at the next prompt. `&!' (background + disown) is what suppresses it,
  # and that's the contract this test pins down.
  #
  # The probe uses `zsh/zpty' to drive a real pty-backed interactive zsh.
  # Reads are timing-based -- pattern-matched reads (`zpty -r p v PAT')
  # are unreliable on zsh 4.3.11. Linux-only because of /proc/$$/exe;
  # the existing concurrency suite is similarly Linux-coupled via
  # `xargs -P'.
  zmodload zsh/zpty 2>/dev/null
  if ! (( ${+modules[zsh/zpty]} )); then
    print "skip: zsh/zpty unavailable"
    return 0
  fi

  local zsh_bin
  zsh_bin=$(readlink /proc/$$/exe 2>/dev/null)
  [[ -x $zsh_bin ]] || zsh_bin=${commands[zsh]}
  if [[ ! -x $zsh_bin ]]; then
    print "skip: no zsh binary located"
    return 0
  fi

  mkdir -p "$TESTDIR/work"

  zpty -b z_probe "$zsh_bin -i --no-rcs -d -f" || {
    fail "zpty -b failed"
    return 1
  }
  sleep 0.3
  zpty -w z_probe "PS1='ZTEST>'"$'\n'
  zpty -w z_probe "setopt MONITOR"$'\n'
  zpty -w z_probe "source '$PLUGIN_DIR/zsh-z.plugin.zsh'"$'\n'
  zpty -w z_probe "cd '$TESTDIR/work'"$'\n'
  zpty -w z_probe "_zshz_precmd"$'\n'
  # Wait for the disowned `zshz --add' to finish writing the datafile.
  sleep 0.5
  # Send a no-op so any pending Done notification surfaces at the next
  # prompt rendering.
  zpty -w z_probe ":"$'\n'
  sleep 0.2
  zpty -w z_probe "exit"$'\n'
  sleep 0.2

  local out= chunk
  while zpty -r z_probe chunk; do out+=$chunk; done 2>/dev/null
  zpty -d z_probe 2>/dev/null

  if [[ $out == *"+ done"* ]]; then
    fail "&! promise broken: interactive precmd surfaced a '+ done' line"
  fi

  # Sanity: SOMETHING landed in the datafile. The interactive zpty
  # session triggers precmd at every prompt (initial, after cd, after
  # the `:'), so the exact rank is whatever-precmd-fired-times rather
  # than 1. We only check that the write path worked at all.
  local rank
  rank=$(zshz_rank_of "$TESTDIR/work")
  if [[ -z $rank ]] || (( rank < 1 )); then
    fail "backgrounded write never landed (rank=$rank)"
  fi
}
# vim: fdm=indent:ts=2:et:sts=2:sw=2:
