# Regression tests for concurrent --add / -x writes.
#
# Before the fix, the read-modify-write cycle was racy: lines was read before
# the lock was acquired, and the lock was held on $datafile (whose inode is
# replaced via mv) so concurrent writers did not actually serialize.
#
# Each writer is spawned as an independent `zsh -c` process via xargs rather
# than as a backgrounded subshell of the test runner. This exercises the
# plugin's flock-based serialization across real OS processes (closer to real
# usage: multiple terminals, each their own zsh) and avoids zsh 4.3.11's
# `&`/`wait` machinery, which segfaults under even light fork load.
#
# The plugin's default lock timeout (ZSHZ_LOCK_TIMEOUT=1s) is meant to keep
# stuck holders from freezing the prompt; under heavy concurrent load that
# bound is too tight and writers would time out and silently drop updates.
# The tests bump the timeout via env so honest contention isn't mistaken
# for a regression.

test_concurrent_add_no_lost_updates() {
  local n=20
  local target="$TESTDIR/target"
  mkdir -p "$target"

  seq 1 $n | xargs -P 4 -I{} \
    env ZSHZ_LOCK_TIMEOUT=30 zsh -c \
      "source '$PLUGIN_DIR/zsh-z.plugin.zsh'; zshz --add '$target'"

  assert_eq "$n" "$(zshz_rank_of "$target")" "$n concurrent adds should produce rank $n"
}

test_concurrent_add_two_paths_each_independent() {
  local n=15 i
  local a="$TESTDIR/a" b="$TESTDIR/b"
  mkdir -p "$a" "$b"

  # Interleave a and b on the input list so xargs runs adds for both paths
  # concurrently (rather than draining one before starting the other).
  {
    for ((i=1; i<=n; i++)); do
      print -- "$a"
      print -- "$b"
    done
  } | xargs -P 4 -I{} \
        env ZSHZ_LOCK_TIMEOUT=30 zsh -c \
          "source '$PLUGIN_DIR/zsh-z.plugin.zsh'; zshz --add '{}'"

  assert_eq "$n" "$(zshz_rank_of "$a")" "$n concurrent adds to a"
  assert_eq "$n" "$(zshz_rank_of "$b")" "$n concurrent adds to b"
}
# vim: fdm=indent:ts=2:et:sts=2:sw=2:
