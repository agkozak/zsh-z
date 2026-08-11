# Concurrent writers must serialize cleanly under develop's lockfile
# design: an external writer running between our read and our `mv'
# must not cause a pre-existing entry to be lost, and both writers'
# new adds must land.
#
# Develop reads the datafile *after* taking the lock (separate stable
# `${datafile}.lock'); master read it before, so two writers could
# each compute a tempfile based on a stale snapshot and the second
# `mv' would silently drop the first writer's update -- including any
# pre-existing entries that were only present in the first writer's
# computed result. The pre-seed in this test is what distinguishes it
# from `test_concurrent_add_two_paths_each_independent', which only
# pins that the two new adds land.
#
# This test deliberately commits to develop's lockfile semantics. The
# `optimistic_concurrency' branch would cleanly drop one of the two
# new adds, and the assertions below would fail; that's intentional.

test_external_writer_during_our_add_serializes() {
  # Without `zsystem flock', the no-lock fallback can't serialize
  # cross-process writers and the second `mv' overwrites the first.
  # Skip when the system module is unavailable (e.g. MobaXterm's Cygwin).
  if ! (( ZSHZ[USE_FLOCK] )); then
    print "skip: zsystem flock unavailable"
    return 0
  fi
  local seeded="$TESTDIR/seeded" a="$TESTDIR/a" b="$TESTDIR/b"
  mkdir -p "$seeded" "$a" "$b"

  # Pre-seed an entry. Under master's broken read-before-lock, this
  # could be lost when two writers race; under develop, it must
  # survive at exactly its seeded rank (neither writer is touching
  # this path).
  zshz_seed "$seeded" 5 60

  # Two writers race for the lockfile. xargs -P 2 spawns them as
  # external `zsh -c' processes (avoids zsh 4.3.11's `&'/`wait'
  # segfault under fork load). The high lock timeout keeps honest
  # contention from being mistaken for a regression.
  #
  # Each writer records its exit status and anything it wrote to stderr.
  # A lost add is otherwise indistinguishable from its causes, and this
  # test has failed intermittently on the MSYS2 CI runner without being
  # reproducible anywhere else -- so the log is dumped on failure below.
  # The status says which of them it was: 2 is a lock-acquisition
  # timeout, 1 a write or permissions failure, and 0 the interesting
  # case, a writer that believes it succeeded, which would mean the lock
  # did not serialize the two of them at all.
  #
  # The writer is a generated script rather than an inline `zsh -c'
  # string, and the input is bare names rather than full paths, because
  # BSD `xargs' caps what an `-I' line may expand to -- 255 bytes, raisable
  # only with `-S', which GNU `xargs' does not accept. macOS's $TMPDIR
  # paths are long enough that an inline script goes over that cap and
  # `xargs' fails the whole run with "command line cannot be assembled,
  # too long". This keeps the assembled line at roughly 120 bytes on the
  # longest-pathed platform we test.
  local writers="$TESTDIR/writers.log" writer="$TESTDIR/writer.zsh"
  export ZSHZ_TEST_WRITER_PLUGIN="$PLUGIN_DIR/zsh-z.plugin.zsh"
  export ZSHZ_TEST_WRITER_ROOT="$TESTDIR"
  export ZSHZ_TEST_WRITER_LOG="$writers"
  cat > "$writer" <<'WRITER'
source "$ZSHZ_TEST_WRITER_PLUGIN"
err=$(zshz --add "$ZSHZ_TEST_WRITER_ROOT/$1" 2>&1)
print -r -- "writer $1 rc=$? err='$err'" >> "$ZSHZ_TEST_WRITER_LOG"
WRITER

  printf '%s\n' "${a:t}" "${b:t}" | ( xargs_P 2 \
    env ZSHZ_LOCK_TIMEOUT=30 zsh "$writer" {} )

  local rank_seeded rank_a rank_b
  rank_seeded=$(zshz_rank_of "$seeded")
  rank_a=$(zshz_rank_of "$a")
  rank_b=$(zshz_rank_of "$b")

  # Dump the evidence before the assertions, so a failure on a platform
  # that cannot be reproduced locally still arrives with its cause
  # attached. Silent on success: run.zsh fails any test that writes to
  # stderr at all.
  if [[ $rank_seeded != 5 || $rank_a != 1 || $rank_b != 1 ]]; then
    local line
    print -u 2 "  --- writer exit statuses ---"
    if [[ -f $writers ]]; then
      while IFS= read -r line; do print -u 2 "    $line"; done < "$writers"
    else
      print -u 2 "    (no writer logged anything at all)"
    fi
    print -u 2 "  --- datafile ---"
    if [[ -f $ZSHZ_DATA ]]; then
      while IFS= read -r line; do print -u 2 "    $line"; done < "$ZSHZ_DATA"
    fi
    print -u 2 "  --- lockfile ---"
    print -u 2 "    $(ls -l ${ZSHZ_DATA}.lock 2>&1)"
  fi

  assert_eq "5" "$rank_seeded" \
    "pre-seeded entry should survive two concurrent --add writers"
  assert_eq "1" "$rank_a" \
    "first concurrent --add should land"
  assert_eq "1" "$rank_b" \
    "second concurrent --add should land"
}

test_many_concurrent_writers_preserve_seeded_entries() {
  # Stronger version of the above: a fleet of writers, each adding a
  # unique path, must not drop any of the N pre-seeded entries.
  # `_zshz_update_datafile' rebuilds the datafile from `lines' on
  # every write, so a stale `lines' (master's bug) would silently
  # delete entries that another in-flight writer just added. With
  # develop's read-after-lock, every writer sees the latest state.
  if ! (( ZSHZ[USE_FLOCK] )); then
    print "skip: zsystem flock unavailable"
    return 0
  fi
  local seeded_count=10 writer_count=10 i
  local -a writer_paths
  for ((i=1; i<=seeded_count; i++)); do
    mkdir -p "$TESTDIR/seed_$i"
    zshz_seed "$TESTDIR/seed_$i" $i 60
  done
  for ((i=1; i<=writer_count; i++)); do
    mkdir -p "$TESTDIR/w_$i"
    writer_paths+=( "$TESTDIR/w_$i" )
  done

  printf '%s\n' "${writer_paths[@]}" | ( xargs_P 4 \
    env ZSHZ_LOCK_TIMEOUT=30 zsh -c \
      "source '$PLUGIN_DIR/zsh-z.plugin.zsh'; zshz --add {}" )

  for ((i=1; i<=seeded_count; i++)); do
    assert_eq "$i" "$(zshz_rank_of "$TESTDIR/seed_$i")" \
      "seeded entry $i must survive $writer_count concurrent writers"
  done
  for ((i=1; i<=writer_count; i++)); do
    assert_eq "1" "$(zshz_rank_of "$TESTDIR/w_$i")" \
      "writer $i's --add must have landed"
  done
}
# vim: fdm=indent:ts=2:et:sts=2:sw=2:
