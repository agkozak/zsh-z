# `_zshz_add_or_remove_path' must not leave behind `${datafile}.NNNNN'
# tempfiles after a write failure or under normal operation.
#
# The plugin uses `${datafile}.${RANDOM}' as a per-write tempfile and
# atomically `mv's it over the datafile. There are several failure
# paths -- the rewrite can fail at write, at chown, or at mv -- and
# each must `rm -f' the tempfile before returning.
#
# `test_concurrent_mixed.zsh' already pins the no-tempfile-after-
# concurrent-ops invariant for the mixed-add/-x case. This file
# pins the single-process failure paths.
#
# A few scenarios from the original LIST.md spec are intentionally
# *not* covered:
#   - Read-only datafile parent dir: tempfile creation itself fails
#     (no tempfile to leak), but the mkdir/touch in `[[ -f $datafile ]]
#     || touch ...' also writes to stderr ahead of `_zshz_add_or_remove_path'.
#   - SIGKILL mid-write: unavoidable leak; no shell-level handler can
#     run after SIGKILL. The plugin doesn't trap signals, so SIGTERM
#     mid-write also leaks. This is a separate "would be nice" item
#     rather than a contract we currently enforce.

# Glob a directory for `${datafile}.<digits>' tempfiles. Returns 0 if
# none exist.
_no_tempfile_in() {
  local dir=$1 base=${ZSHZ_DATA:t}
  local -a leftovers
  leftovers=( "$dir"/${base}.<->(N) )
  (( ${#leftovers} == 0 )) || \
    fail "tempfile(s) leftover: ${(j:, :)leftovers}"
}

test_no_tempfile_after_normal_add() {
  mkdir -p "$TESTDIR/p"
  zshz --add "$TESTDIR/p"
  _no_tempfile_in "$TESTDIR"
}

test_no_tempfile_after_many_sequential_adds() {
  # Guards against a bug where each `--add' leaks one tempfile, which
  # would surface as accumulation rather than a single leftover.
  local i
  for ((i=0; i<20; i++)); do
    mkdir -p "$TESTDIR/p_$i"
    zshz --add "$TESTDIR/p_$i"
  done
  _no_tempfile_in "$TESTDIR"
}

test_no_tempfile_after_mv_failure() {
  # Mock `${ZSHZ[MV]}' with `false' so the rename step always fails.
  # The plugin's failure path (`(( write_ret != 0 )) && rm -f tempfile')
  # must clean up the tempfile it just wrote.
  mkdir -p "$TESTDIR/p"
  zshz_seed "$TESTDIR/seed" 5 60   # pre-existing entry to verify it survives
  ZSHZ[MV]=false
  zshz --add "$TESTDIR/p"
  ZSHZ[MV]=mv   # restore for later tests in the same runner

  _no_tempfile_in "$TESTDIR"
  # Datafile content should be unchanged because the mv never landed.
  assert_eq "5" "$(zshz_rank_of "$TESTDIR/seed")" \
    "pre-existing entry should be unchanged when mv fails"
  assert_eq "" "$(zshz_rank_of "$TESTDIR/p")" \
    "new entry should not appear when the rename failed"
}

test_no_tempfile_after_lock_timeout() {
  # The lock-timeout path returns before opening the tempfile, so
  # there's nothing to clean up. This test pins that property -- a
  # future refactor that opens the tempfile before `flock' would
  # surface as a leak here.
  if ! (( ZSHZ[USE_FLOCK] )); then
    print "skip: zsystem flock unavailable"
    return 0
  fi

  mkdir -p "$TESTDIR/p"
  touch "${ZSHZ_DATA}.lock"

  zsh --no-rcs -c "
    zmodload zsh/system
    zsystem flock '${ZSHZ_DATA}.lock'
    sleep 3
  " &!
  local holder=$!
  sleep 0.2

  ZSHZ_LOCK_TIMEOUT=1 zshz --add "$TESTDIR/p"
  kill $holder 2>/dev/null

  _no_tempfile_in "$TESTDIR"
}
# vim: fdm=indent:ts=2:et:sts=2:sw=2:
