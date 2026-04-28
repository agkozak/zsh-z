# -c flag: restrict matches to subdirectories of $PWD.
#
# Internally this prepends "$PWD " to the search string and anchors the match
# at start (zsh-z.plugin.zsh:765, ~858).

test_c_flag_picks_match_under_pwd() {
  mkdir -p "$TESTDIR/here/sub" "$TESTDIR/elsewhere/sub"
  zshz --add "$TESTDIR/here/sub"
  zshz --add "$TESTDIR/elsewhere/sub"

  cd "$TESTDIR/here"
  local out=$(zshz -ce sub)
  assert_eq "$TESTDIR/here/sub" "$out" "-c should pick the match inside PWD subtree"
}

test_c_flag_excludes_paths_outside_pwd() {
  mkdir -p "$TESTDIR/here" "$TESTDIR/elsewhere/sub"
  zshz --add "$TESTDIR/elsewhere/sub"

  cd "$TESTDIR/here"
  local out
  out=$(zshz -ce sub 2> /dev/null)
  local rc=$?
  assert_ne "0" "$rc" "-c should not match outside PWD subtree"
  assert_eq "" "$out" "no output when nothing under PWD matches"
}
