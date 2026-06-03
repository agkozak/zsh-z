# -c flag: restrict matches to subdirectories of $PWD.
#
# The `-c` path prefixes the query with "$PWD " and then matches only from the
# start of candidate paths, so results must stay within the current subtree.

test_c_flag_picks_match_under_pwd() {
  mkdir -p "$TESTDIR/here/sub" "$TESTDIR/elsewhere/sub"
  zshz --add "$TESTDIR/here/sub"
  zshz --add "$TESTDIR/elsewhere/sub"

  cd "$TESTDIR/here"
  local out
  out=$(zshz -ce sub)
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
# vim: fdm=indent:ts=2:et:sts=2:sw=2:
