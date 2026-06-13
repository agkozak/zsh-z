#!/usr/bin/env zsh
# Test runner for Zsh-z. Exits non-zero if any test fails.
#
# A test is a function named test_* defined in any tests/test_*.zsh file.
# Each test runs against a fresh ZSHZ_DATA in a tempdir; any non-empty stderr
# produced by a test causes it to fail (so WARN_CREATE_GLOBAL warnings and
# unintended errors both surface).

setopt EXTENDED_GLOB
# Zsh 4.3.11 does not have PIPE_FAIL.
(( ${+options[pipefail]} )) && setopt PIPE_FAIL

TESTS_DIR=${0:h}
[[ $TESTS_DIR == $0 ]] && TESTS_DIR=.
TESTS_DIR=$(builtin cd "$TESTS_DIR" && builtin pwd -P) || exit 2
PLUGIN_DIR=$(builtin cd "$TESTS_DIR/.." && builtin pwd -P) || exit 2

source "$PLUGIN_DIR/zsh-z.plugin.zsh"
source "$TESTS_DIR/test_helpers.zsh"

# Probe once and export the result so per-test subshells skip the
# re-probe. The fork the probe avoids matters on zsh 4.3.11.
_xargs_supports_P >/dev/null

typeset -ga _test_files
_test_files=( "$TESTS_DIR"/test_*.zsh(.N) )
typeset -ga _test_fns

# Collect test functions from the sourced files, then sort by name so the
# execution order is stable.
for _f in $_test_files; do
  [[ ${_f:t} == test_helpers.zsh ]] && continue
  source "$_f"
done

for _fn in ${(k)functions}; do
  [[ $_fn == test_* ]] && _test_fns+=( $_fn )
done
_test_fns=( ${(o)_test_fns} )

# If names were passed on the command line, run only those tests. Each arg is
# matched as a glob against test function names, so prefixes work too, and
# several patterns may be combined -- a test runs if it matches any of them:
#   zsh tests/run.zsh test_concurrent_add_no_lost_updates
#   zsh tests/run.zsh 'test_concurrent_*'
#   zsh tests/run.zsh 'test_uncommon_*' 'test_special_chars_*'
if (( $# )); then
  # Keep each test whose name matches at least one pattern (a union). A single
  # `${(M)_test_fns:#${~^@}}' can't express that -- with several patterns it
  # selects nothing -- so walk the patterns explicitly. `${~_pat}' is required:
  # a bare parameter on the right of `==' is matched *literally* (its glob
  # metacharacters are inert unless GLOB_SUBST is set), so `${~}' forces it to
  # be read as a pattern. This holds on every Zsh, 4.3.11 included.
  typeset -a _selected
  typeset _fn _pat
  for _fn in $_test_fns; do
    for _pat in "$@"; do
      [[ $_fn == ${~_pat} ]] && { _selected+=( $_fn ); break }
    done
  done
  _test_fns=( $_selected )
  if (( ! ${#_test_fns} )); then
    print -u 2 "No tests matched: $*"
    exit 2
  fi
fi

typeset -gi total=0 passed=0 failed=0
typeset -ga failures

for fn in $_test_fns; do
  (( total++ ))

  # `mktemp -d -t prefix' is non-portable: GNU substitutes the X's in
  # `prefix' in place, but Solaris/BSD mktemp treats `prefix' as a
  # literal and appends its own suffix, producing names like
  # `/tmp/zshz-test..XXXX' -- the extra dot breaks tests that assert no
  # `..' appears in stored paths. The direct-template form is portable.
  TESTDIR=$(mktemp -d "${TMPDIR:-/tmp}/zshz-test.XXXXXX") || { print -u 2 "mktemp failed"; exit 2; }
  # Canonicalize: on macOS $TMPDIR lives under /var (a symlink to /private/var)
  # and carries a trailing slash, so the raw path differs from the symlink- and
  # slash-normalized one Zsh-z stores. Resolve it once here, the same way
  # TESTS_DIR/PLUGIN_DIR are resolved above, so tests built from $TESTDIR match.
  TESTDIR=$(builtin cd "$TESTDIR" && builtin pwd -P) || { print -u 2 "cd failed"; exit 2; }
  export ZSHZ_DATA="$TESTDIR/.z"
  STDERR_LOG="$TESTDIR/stderr.log"
  STDOUT_LOG="$TESTDIR/stdout.log"

  # Run the test in a subshell so cd / env / option changes don't leak.
  ( ZSHZ_DEBUG=1; cd "$TESTDIR"; "$fn" ) > "$STDOUT_LOG" 2> "$STDERR_LOG"
  rc=$?

  reason=""
  (( rc != 0 )) && reason="rc=$rc"
  if [[ -s $STDERR_LOG ]]; then
    [[ -n $reason ]] && reason="$reason; "
    reason="${reason}stderr"
  fi

  if [[ -z $reason ]]; then
    (( passed++ ))
    print "PASS  $fn"
  else
    (( failed++ ))
    failures+=( "$fn" )
    print "FAIL  $fn ($reason)"
    if [[ -s $STDOUT_LOG ]]; then
      print "  --- stdout ---"
      sed 's/^/  /' "$STDOUT_LOG"
    fi
    if [[ -s $STDERR_LOG ]]; then
      print "  --- stderr ---"
      sed 's/^/  /' "$STDERR_LOG"
    fi
  fi

  rm -rf "$TESTDIR"
  unset TESTDIR ZSHZ_DATA STDERR_LOG STDOUT_LOG
done

print
print "Results: $passed passed, $failed failed of $total"
(( failed == 0 ))
# vim: fdm=indent:ts=2:et:sts=2:sw=2:
