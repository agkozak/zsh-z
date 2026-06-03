# Round-trip behaviour for paths containing characters that are special to
# the shell, glob engine, or both. Exercises the `${(q)2}' quoting in
# `_zshz_update_datafile' and the escape list in `_zshz_find_matches'.
#
# Each test creates a real directory (so the missing-directory prune
# doesn't drop the entry), `--add's it, verifies the entry is reachable
# via `zshz -e <substring>' and visible in `zshz -l', then removes it
# with `zshz -x' and confirms it's gone.

test_path_with_spaces_round_trip() {
  local p="$TESTDIR/has spaces/inner"
  mkdir -p "$p"
  zshz --add "$p"
  assert_eq "1" "$(zshz_rank_of "$p")" "add should land path with spaces"

  local out
  out=$(zshz -e spaces)
  assert_eq "$p" "$out" "search should find path with spaces"

  zshz -x "$p"
  assert_eq "" "$(zshz_rank_of "$p")" "remove should clear path with spaces"
}

test_path_with_brackets_round_trip() {
  local p="$TESTDIR/has[brackets]/inner"
  mkdir -p "$p"
  zshz --add "$p"
  assert_eq "1" "$(zshz_rank_of "$p")" "add should land path with []"

  local out
  out=$(zshz -e brackets)
  assert_eq "$p" "$out" "search should find path with []"

  zshz -x "$p"
  assert_eq "" "$(zshz_rank_of "$p")" "remove should clear path with []"
}

test_path_with_star_round_trip() {
  local p="$TESTDIR/has*star/inner"
  mkdir -p "$p"
  zshz --add "$p"
  assert_eq "1" "$(zshz_rank_of "$p")" "add should land path with *"

  local out
  out=$(zshz -e star)
  assert_eq "$p" "$out" "search should find path with *"

  zshz -x "$p"
  assert_eq "" "$(zshz_rank_of "$p")" "remove should clear path with *"
}

test_path_with_question_mark_round_trip() {
  local p="$TESTDIR/has?question/inner"
  mkdir -p "$p"
  zshz --add "$p"
  assert_eq "1" "$(zshz_rank_of "$p")" "add should land path with ?"

  local out
  out=$(zshz -e question)
  assert_eq "$p" "$out" "search should find path with ?"

  zshz -x "$p"
  assert_eq "" "$(zshz_rank_of "$p")" "remove should clear path with ?"
}

test_path_with_backtick_round_trip() {
  local p="$TESTDIR"'/has`backtick/inner'
  mkdir -p "$p"
  zshz --add "$p"
  assert_eq "1" "$(zshz_rank_of "$p")" "add should land path with backtick"

  local out
  out=$(zshz -e backtick)
  assert_eq "$p" "$out" "search should find path with backtick"

  zshz -x "$p"
  assert_eq "" "$(zshz_rank_of "$p")" "remove should clear path with backtick"
}

test_path_with_single_quote_round_trip() {
  local p="$TESTDIR/has'quote/inner"
  mkdir -p "$p"
  zshz --add "$p"
  assert_eq "1" "$(zshz_rank_of "$p")" "add should land path with single quote"

  local out
  out=$(zshz -e quote)
  assert_eq "$p" "$out" "search should find path with single quote"

  zshz -x "$p"
  assert_eq "" "$(zshz_rank_of "$p")" "remove should clear path with single quote"
}

test_path_with_dollar_sign_round_trip() {
  local p="$TESTDIR"'/has$dollar/inner'
  mkdir -p "$p"
  zshz --add "$p"
  assert_eq "1" "$(zshz_rank_of "$p")" "add should land path with \$"

  local out
  out=$(zshz -e dollar)
  assert_eq "$p" "$out" "search should find path with \$"

  zshz -x "$p"
  assert_eq "" "$(zshz_rank_of "$p")" "remove should clear path with \$"
}

test_path_with_mixed_special_chars_round_trip() {
  # All seven special chars in one path. We search by a substring that
  # avoids the chars themselves so the search-side glob doesn't have
  # to deal with them -- this test pins the *quoting* round-trip, not
  # the search-side handling of every meta in a query.
  local p="$TESTDIR"'/mixed [abc] $var `tick` *star ?q '"'q'/inner"
  mkdir -p "$p"
  zshz --add "$p"
  assert_eq "1" "$(zshz_rank_of "$p")" "add should land path with mixed special chars"

  local out
  out=$(zshz -e mixed)
  assert_eq "$p" "$out" "search should find the mixed-specials entry"

  zshz -x "$p"
  assert_eq "" "$(zshz_rank_of "$p")" "remove should clear the mixed-specials entry"
}
# vim: fdm=indent:ts=2:et:sts=2:sw=2:
