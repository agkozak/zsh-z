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

typeset -ga _test_files
while IFS= read -r _f; do
  _test_files+=( "$_f" )
done < <(find "$TESTS_DIR" -maxdepth 1 -type f -name 'test_*.zsh' | LC_ALL=C sort)
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

typeset -gi total=0 passed=0 failed=0
typeset -ga failures

for fn in $_test_fns; do
  (( total++ ))

  TESTDIR=$(mktemp -d -t zshz-test.XXXXXX) || { print -u 2 "mktemp failed"; exit 2; }
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
