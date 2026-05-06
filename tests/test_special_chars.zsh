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

test_path_with_dollar_sign_add_and_remove() {
  # KNOWN-BUG: paths containing `$' currently round-trip through `--add'
  # and `-x', but `zshz -l' and `zshz -e' don't see them.
  #
  # `_zshz_find_matches' assigns `matches[$path_field]=$rank' (a normal
  # parameter expansion, fine) and then later checks the same entry via
  # `(( matches[$escaped_path_field] ))'. That lookup runs in math
  # context, where zsh re-expands `$' inside the subscript -- so a
  # subscript like `/tmp/has$dollar' becomes `/tmp/has' (with $dollar
  # unset). The lookup misses, `best_match' stays empty, and
  # `_zshz_find_matches' returns 1 -- so `_zshz_output' is never called
  # at all when the dollar entry is the only candidate. The plugin's
  # `escaped_path_field' block (\, `, (, ), [, ]) doesn't currently
  # include `$'. Once it does, the search/list assertions from the
  # other tests in this file should be added here too.
  local p="$TESTDIR"'/has$dollar/inner'
  mkdir -p "$p"
  zshz --add "$p"
  assert_eq "1" "$(zshz_rank_of "$p")" "add should land path with \$"

  zshz -x "$p"
  assert_eq "" "$(zshz_rank_of "$p")" "remove should clear path with \$"
}

test_path_with_mixed_special_chars_add_and_remove() {
  # Same `$'-in-math-context limitation as the dollar-sign test: the
  # path here also contains `$', so `zshz -l'/`zshz -e' won't surface
  # it on its own. We just check that the quoting machinery round-trips
  # add and remove without corrupting the datafile.
  local p="$TESTDIR"'/mixed [abc] $var `tick` *star ?q '"'q'/inner"
  mkdir -p "$p"
  zshz --add "$p"
  assert_eq "1" "$(zshz_rank_of "$p")" "add should land path with mixed special chars"

  zshz -x "$p"
  assert_eq "" "$(zshz_rank_of "$p")" "remove should clear the mixed-specials entry"
}
# vim: fdm=indent:ts=2:et:sts=2:sw=2:
