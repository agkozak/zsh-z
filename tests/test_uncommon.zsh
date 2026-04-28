# ZSHZ_UNCOMMON: shrink the destination path to the shortest level that still
# preserves the count of the search pattern in the path. Distinct from the
# default behavior, which prefers the common root of all matches when one
# exists. (zsh-z.plugin.zsh:849-876, ~591)

test_uncommon_shrinks_to_keep_pattern_count() {
  # /foo/bar/foo/bar contains "foo" twice; with query "foo", UNCOMMON should
  # shrink to /foo/bar/foo (the shortest ancestor that still has both "foo"s).
  mkdir -p "$TESTDIR/foo/bar/foo/bar"
  zshz --add "$TESTDIR/foo/bar/foo/bar"
  ZSHZ_UNCOMMON=1
  local out=$(zshz -e foo)
  assert_eq "$TESTDIR/foo/bar/foo" "$out" "UNCOMMON should keep both 'foo' occurrences"
}

test_default_with_single_match_returns_full_path() {
  mkdir -p "$TESTDIR/foo/bar/foo/bar"
  zshz --add "$TESTDIR/foo/bar/foo/bar"
  local out=$(zshz -e foo)
  assert_eq "$TESTDIR/foo/bar/foo/bar" "$out" "default with single match should return the full path"
}

test_default_returns_common_root_when_one_exists() {
  mkdir -p "$TESTDIR/cr/aaa" "$TESTDIR/cr/bbb"
  local now=$EPOCHSECONDS
  print -l \
    "$TESTDIR/cr|1|$((now - 60))" \
    "$TESTDIR/cr/aaa|100|$((now - 60))" \
    "$TESTDIR/cr/bbb|50|$((now - 60))" \
    > "$ZSHZ_DATA"
  local out=$(zshz -e cr)
  assert_eq "$TESTDIR/cr" "$out" "default should pick the common-root entry over the highest-rank child"
}
