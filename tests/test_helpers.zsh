# Test helpers for Zsh-z. Sourced by tests/run.zsh and by each test_*.zsh.

# Fail with a message
fail() {
  print -u 2 "  $*"
  return 1
}

assert_eq() {
  local expected=$1 actual=$2 msg=${3:-}
  [[ $expected == $actual ]] && return 0
  fail "${msg:+$msg: }expected '$expected', got '$actual'"
}

assert_ne() {
  local unexpected=$1 actual=$2 msg=${3:-}
  [[ $unexpected != $actual ]] && return 0
  fail "${msg:+$msg: }expected anything but '$unexpected', got '$actual'"
}

assert_contains() {
  local needle=$1 haystack=$2 msg=${3:-}
  [[ $haystack == *$needle* ]] && return 0
  fail "${msg:+$msg: }expected '$haystack' to contain '$needle'"
}

assert_not_contains() {
  local needle=$1 haystack=$2 msg=${3:-}
  [[ $haystack != *$needle* ]] && return 0
  fail "${msg:+$msg: }expected '$haystack' not to contain '$needle'"
}

assert_file_exists() {
  [[ -f $1 ]] && return 0
  fail "expected file '$1' to exist"
}

# Read the rank for $1 from the current $ZSHZ_DATA
zshz_rank_of() {
  local p=$1
  [[ -f $ZSHZ_DATA ]] || { print ""; return; }
  awk -F'|' -v p="$p" '$1==p { print $2 }' "$ZSHZ_DATA"
}

# Read the entire datafile, sorted by path, for stable comparisons
zshz_dump() {
  [[ -f $ZSHZ_DATA ]] && sort "$ZSHZ_DATA"
}
