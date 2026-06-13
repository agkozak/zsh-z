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

test_path_with_backslash_round_trip() {
  # A literal backslash is the acid test for the `print -r' discipline: the
  # datafile stores literal paths, so any emission without `-r' silently
  # collapses an escape (`\t' -> a real tab) on the way back out or on the
  # next rewrite. `\there' is backslash + "there", NOT a tab.
  #
  # Note: `zshz_rank_of' can't be used here -- its `awk -v' itself turns a
  # `\t' in the path into a tab -- so the on-disk checks read the datafile
  # directly and compare with quoted (literal) assertions.
  _test_skip_no_backslash_in_filename && { print "skip: no backslash-in-filename support"; return 0 }
  local p="$TESTDIR/back\there/inner"
  mkdir -p "$p"
  zshz --add "$p"
  assert_contains "$p|1|" "$(< $ZSHZ_DATA)" "add should land the backslash path verbatim"

  local out
  out=$(zshz -e there)
  assert_eq "$p" "$out" "search should return the backslash path verbatim"

  zshz -x "$p"
  # The entry was the only one, so a correct remove empties the datafile;
  # a corrupting remove would leave a mangled residue behind.
  assert_eq "" "$(< $ZSHZ_DATA)" "remove should clear the backslash path with no residue"
}

test_path_with_backslash_survives_rewrite() {
  # Adding a second directory rewrites the whole datafile, carrying the
  # backslash entry through `_zshz_update_datafile'. It must come out byte-
  # identical, not with its escape collapsed.
  _test_skip_no_backslash_in_filename && { print "skip: no backslash-in-filename support"; return 0 }
  local p="$TESTDIR/keep\there/inner" q="$TESTDIR/other"
  mkdir -p "$p" "$q"
  zshz --add "$p"
  zshz --add "$q"
  assert_contains "$p|1|" "$(< $ZSHZ_DATA)" \
      "backslash path should survive an add-triggered rewrite verbatim"
}

test_path_with_backslash_survives_unrelated_remove() {
  # `z -x' of a *different* directory rewrites the datafile, carrying every
  # other line through the remove path verbatim. A backslash entry that is
  # merely a bystander must not have its escape collapsed.
  _test_skip_no_backslash_in_filename && { print "skip: no backslash-in-filename support"; return 0 }
  local p="$TESTDIR/stay\there/inner" q="$TESTDIR/gone"
  mkdir -p "$p" "$q"
  zshz --add "$p"
  zshz --add "$q"
  zshz -x "$q"
  assert_contains "$p|1|" "$(< $ZSHZ_DATA)" \
      "backslash bystander should survive an unrelated remove verbatim"
}

test_path_with_backslash_listed_verbatim() {
  # `zshz -l' is a different emission path from `-e'; make sure it, too,
  # prints the backslash literally rather than collapsing it.
  _test_skip_no_backslash_in_filename && { print "skip: no backslash-in-filename support"; return 0 }
  local p="$TESTDIR/list\there/inner"
  mkdir -p "$p"
  zshz --add "$p"

  local out
  out=$(zshz -l)
  assert_contains "$p" "$out" "list output should contain the backslash path verbatim"
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
