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
  [[ $expected == "$actual" ]] && return 0
  fail "${msg:+$msg: }expected '$expected', got '$actual'"
}

assert_ne() {
  local unexpected actual msg
  unexpected="$1"
  actual="$2"
  msg="${3:-}"
  [[ $unexpected != "$actual" ]] && return 0
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

# Drop-in replacement for `xargs -P NPROC -I {} CMD ARGS...'.
#
# Solaris (and other AT&T-derived) `xargs' don't support `-P'. Where the
# system `xargs' has it, we use it -- the concurrency tests rely on
# spawning external `zsh -c' processes to dodge zsh 4.3.11's `&'/`wait'
# segfault under fork load. Where `-P' isn't available (Solaris with a
# modern zsh), `&'+`wait' works and we fall back to that. The probe
# result is cached in `_XARGS_P_OK'.
#
# NPROC is honored only on the `xargs -P' path; the fallback spawns
# every item at once -- fine for the small N (<=30) the suite uses.
#
# IMPORTANT: callers must invoke this inside `( ... )' on the right side
# of a pipe, e.g. `producer | ( xargs_P 4 cmd args )'. Two reasons:
# (1) zsh does NOT fork the right side of a pipe when it's a function or
# block, so without the parens the `exec' below would replace the
# caller's shell.  (2) On zsh 4.3.11, an internal `( ... )' inside a
# function-on-pipe-right triggers SIGBUS at higher fork counts -- the
# parens have to be at the call site, not in the function body.
xargs_P() {
  local nproc=$1; shift
  if _xargs_supports_P; then
    exec xargs -P "$nproc" -I {} "$@"
  fi
  local line a
  local -a pids cmd
  while IFS= read -r line; do
    cmd=()
    for a in "$@"; do
      cmd+=( "${a//\{\}/$line}" )
    done
    "${cmd[@]}" &
    pids+=( $! )
  done
  (( ${#pids} )) && wait "${pids[@]}" 2>/dev/null
}

_xargs_supports_P() {
  if [[ -z ${_XARGS_P_OK+set} ]]; then
    # `< /dev/null' rather than `: | xargs ...': fewer forks per probe,
    # which matters on zsh 4.3.11 where the fork machinery is fragile.
    # `-gx' exports the cache so test subshells skip the re-probe.
    if xargs -P 1 -I {} true < /dev/null 2>/dev/null; then
      typeset -gx _XARGS_P_OK=1
    else
      typeset -gx _XARGS_P_OK=0
    fi
  fi
  (( _XARGS_P_OK ))
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
# vim: fdm=indent:ts=2:et:sts=2:sw=2:
