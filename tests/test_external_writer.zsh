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
  printf '%s\n' "$a" "$b" | xargs -P 2 -I {} \
    env ZSHZ_LOCK_TIMEOUT=30 zsh -c \
      "source '$PLUGIN_DIR/zsh-z.plugin.zsh'; zshz --add {}"

  assert_eq "5" "$(zshz_rank_of "$seeded")" \
    "pre-seeded entry should survive two concurrent --add writers"
  assert_eq "1" "$(zshz_rank_of "$a")" \
    "first concurrent --add should land"
  assert_eq "1" "$(zshz_rank_of "$b")" \
    "second concurrent --add should land"
}

test_many_concurrent_writers_preserve_seeded_entries() {
  # Stronger version of the above: a fleet of writers, each adding a
  # unique path, must not drop any of the N pre-seeded entries.
  # `_zshz_update_datafile' rebuilds the datafile from `lines' on
  # every write, so a stale `lines' (master's bug) would silently
  # delete entries that another in-flight writer just added. With
  # develop's read-after-lock, every writer sees the latest state.
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

  printf '%s\n' "${writer_paths[@]}" | xargs -P 4 -I {} \
    env ZSHZ_LOCK_TIMEOUT=30 zsh -c \
      "source '$PLUGIN_DIR/zsh-z.plugin.zsh'; zshz --add {}"

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
