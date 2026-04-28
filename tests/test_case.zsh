# ZSHZ_CASE: 'smart', 'ignore', or default.
#
# Default: case-sensitive match preferred, case-insensitive as fallback.
# 'smart':   case-insensitive only if query is all lowercase.
# 'ignore':  always case-insensitive.
# (zsh-z.plugin.zsh:681-688)

test_case_default_falls_back_to_insensitive() {
  mkdir -p "$TESTDIR/Foo/Bar"
  zshz --add "$TESTDIR/Foo/Bar"
  local out=$(zshz -e bar)
  assert_eq "$TESTDIR/Foo/Bar" "$out" "default mode should fall back to case-insensitive"
}

test_case_default_prefers_sensitive_when_both_available() {
  mkdir -p "$TESTDIR/Foo/Bar" "$TESTDIR/foo/bar"
  zshz --add "$TESTDIR/Foo/Bar"
  zshz --add "$TESTDIR/foo/bar"
  local out=$(zshz -e bar)
  assert_eq "$TESTDIR/foo/bar" "$out" "default mode should prefer case-sensitive match"
}

test_case_ignore_always_insensitive() {
  mkdir -p "$TESTDIR/Foo/Bar"
  zshz --add "$TESTDIR/Foo/Bar"
  ZSHZ_CASE=ignore
  local out=$(zshz -e bar)
  assert_eq "$TESTDIR/Foo/Bar" "$out" "ZSHZ_CASE=ignore should match case-insensitively"
}

test_case_smart_lowercase_query_is_insensitive() {
  mkdir -p "$TESTDIR/Foo/Bar"
  zshz --add "$TESTDIR/Foo/Bar"
  ZSHZ_CASE=smart
  local out=$(zshz -e bar)
  assert_eq "$TESTDIR/Foo/Bar" "$out" "smart + lowercase query should match insensitively"
}

test_case_smart_uppercase_query_is_strict() {
  mkdir -p "$TESTDIR/foo/bar"
  zshz --add "$TESTDIR/foo/bar"
  ZSHZ_CASE=smart
  local out
  out=$(zshz -e BAR 2> /dev/null)
  local rc=$?
  assert_ne "0" "$rc" "smart + uppercase query should not fall back to insensitive"
  assert_eq "" "$out" "smart + uppercase query should not match a lowercase path"
}
