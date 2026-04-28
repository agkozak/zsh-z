# Regression tests for concurrent --add / -x writes.
#
# Before the fix, the read-modify-write cycle was racy: lines was read before
# the lock was acquired, and the lock was held on $datafile (whose inode is
# replaced via mv) so concurrent writers did not actually serialize.

test_concurrent_add_no_lost_updates() {
  local n=20 i
  local target="$TESTDIR/target"
  mkdir -p "$target"

  for i in $(seq 1 $n); do
    ( zshz --add "$target" ) &
  done
  wait

  assert_eq "$n" "$(zshz_rank_of "$target")" "$n concurrent adds should produce rank $n"
}

test_concurrent_add_two_paths_each_independent() {
  local n=15 i
  local a="$TESTDIR/a" b="$TESTDIR/b"
  mkdir -p "$a" "$b"

  for i in $(seq 1 $n); do
    ( zshz --add "$a" ) &
    ( zshz --add "$b" ) &
  done
  wait

  assert_eq "$n" "$(zshz_rank_of "$a")" "$n concurrent adds to a"
  assert_eq "$n" "$(zshz_rank_of "$b")" "$n concurrent adds to b"
}
