# Round-trip behaviour for paths containing non-ASCII characters.
#
# Three scripts represent distinct UTF-8 categories: Latin-extended
# (single-codepoint accented chars), CJK (multi-byte ideographs), and
# Cyrillic (a separate alphabet exercising any locale-dependent paths).
# Each test creates the directory on disk so the missing-directory
# prune doesn't drop the entry, then verifies add, search by ASCII or
# native substring, listing, and remove via `-x'.

test_path_with_latin_extended_round_trip() {
  local p="$TESTDIR/café/résumé"
  mkdir -p "$p"
  zshz --add "$p"
  assert_eq "1" "$(zshz_rank_of "$p")" "add should land Latin-extended path"

  local out
  out=$(zshz -e café)
  assert_eq "$p" "$out" "search by native substring should find Latin-extended path"

  local list
  list=$(zshz -l)
  assert_contains "café" "$list" "list should include Latin-extended path"

  zshz -x "$p"
  assert_eq "" "$(zshz_rank_of "$p")" "remove should clear Latin-extended path"
}

test_path_with_cjk_round_trip() {
  local p="$TESTDIR/日本語/プロジェクト"
  mkdir -p "$p"
  zshz --add "$p"
  assert_eq "1" "$(zshz_rank_of "$p")" "add should land CJK path"

  local out
  out=$(zshz -e 日本語)
  assert_eq "$p" "$out" "search by CJK substring should find CJK path"

  local list
  list=$(zshz -l)
  assert_contains "日本語" "$list" "list should include CJK path"

  zshz -x "$p"
  assert_eq "" "$(zshz_rank_of "$p")" "remove should clear CJK path"
}

test_path_with_cyrillic_round_trip() {
  local p="$TESTDIR/привет/мир"
  mkdir -p "$p"
  zshz --add "$p"
  assert_eq "1" "$(zshz_rank_of "$p")" "add should land Cyrillic path"

  local out
  out=$(zshz -e привет)
  assert_eq "$p" "$out" "search by Cyrillic substring should find Cyrillic path"

  local list
  list=$(zshz -l)
  assert_contains "привет" "$list" "list should include Cyrillic path"

  zshz -x "$p"
  assert_eq "" "$(zshz_rank_of "$p")" "remove should clear Cyrillic path"
}

test_ascii_substring_finds_path_with_unicode() {
  # Mixed ASCII / non-ASCII in the same path component, searched by
  # the ASCII portion. Confirms substring matching crosses byte
  # boundaries cleanly when the search query stays in ASCII.
  local p="$TESTDIR/proj-café-2026/notes"
  mkdir -p "$p"
  zshz --add "$p"

  local out
  out=$(zshz -e proj)
  assert_eq "$p" "$out" "ASCII query should find a path that contains non-ASCII chars elsewhere"
}
# vim: fdm=indent:ts=2:et:sts=2:sw=2:
