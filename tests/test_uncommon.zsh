# ZSHZ_UNCOMMON: shrink the chosen destination to the shortest level that still
# preserves how many times the search pattern appears in the path. Distinct
# from the default behavior, which prefers a shared common root when one exists.

test_uncommon_shrinks_to_keep_pattern_count() {
  # /foo/bar/foo/bar contains "foo" twice; with query "foo", UNCOMMON should
  # shrink to /foo/bar/foo (the shortest ancestor that still has both "foo"s).
  mkdir -p "$TESTDIR/foo/bar/foo/bar"
  zshz --add "$TESTDIR/foo/bar/foo/bar"
  ZSHZ_UNCOMMON=1
  local out
  out=$(zshz -e foo)
  assert_eq "$TESTDIR/foo/bar/foo" "$out" "UNCOMMON should keep both 'foo' occurrences"
}

test_default_with_single_match_returns_full_path() {
  mkdir -p "$TESTDIR/foo/bar/foo/bar"
  zshz --add "$TESTDIR/foo/bar/foo/bar"
  local out
  out=$(zshz -e foo)
  assert_eq "$TESTDIR/foo/bar/foo/bar" "$out" "default with single match should return the full path"
}

test_default_returns_common_root_when_one_exists() {
  mkdir -p "$TESTDIR/cr/aaa" "$TESTDIR/cr/bbb"
  zshz_seed "$TESTDIR/cr" 1 60
  zshz_seed "$TESTDIR/cr/aaa" 100 60
  zshz_seed "$TESTDIR/cr/bbb" 50 60
  local out
  out=$(zshz -e cr)
  assert_eq "$TESTDIR/cr" "$out" "default should pick the common-root entry over the highest-rank child"
}
# vim: fdm=indent:ts=2:et:sts=2:sw=2:
