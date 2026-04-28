# Test helpers for Zsh-z. Sourced by tests/run.zsh and by each test_*.zsh.

# Fail with a message
fail() {
  print -u 2 "  $*"
  return 1
}

assert_eq() {
  local expected actual msg
  expected="$1"
  actual="$2"
  msg="${3:-}"
  [[ $expected == $actual ]] && return 0
  fail "${msg:+$msg: }expected '$expected', got '$actual'"
}

assert_ne() {
  local unexpected actual msg
  unexpected="$1"
  actual="$2"
  msg="${3:-}"
  [[ $unexpected != $actual ]] && return 0
  fail "${msg:+$msg: }expected anything but '$unexpected', got '$actual'"
}

assert_contains() {
  local needle haystack msg
  needle="$1"
  haystack="$2"
  msg="${3:-}"
  [[ $haystack == *$needle* ]] && return 0
  fail "${msg:+$msg: }expected '$haystack' to contain '$needle'"
}

assert_not_contains() {
  local needle haystack msg
  needle="$1"
  haystack="$2"
  msg="${3:-}"
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

# Append a synthetic entry to $ZSHZ_DATA with timestamp = now - SECONDS_AGO.
zshz_seed() {
  local path rank seconds_ago
  path="$1"
  rank="$2"
  seconds_ago="${3:-0}"
  print "${path}|${rank}|$(( EPOCHSECONDS - seconds_ago ))" >> "$ZSHZ_DATA"
}

# Run BODY in a fresh `zsh --no-rcs -c` after binding Tab to expand-or-complete
# and sourcing the plugin. Tests that need different setup before sourcing
# (e.g. _Z_CMD=zoo, or a non-default Tab binding as captured baseline) must
# use raw `zsh -c`.
zshz_in_fresh_shell() {
  zsh --no-rcs -c "
    bindkey -M main '^I' expand-or-complete
    source '$PLUGIN_DIR/zsh-z.plugin.zsh'
    $1
  "
}
