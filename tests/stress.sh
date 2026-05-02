#!/usr/bin/env bash
# Stress Zsh-z concurrent --add without relying on the harness shell's
# fork-and-wait, which segfaults on zsh 4.3.11.
#
# Usage:  stress.sh [zsh-binary]   (default: zsh)
#         N=200 PARALLEL=8 stress.sh ~/bin/zsh-4.3.11
set -eu
ZSH_BIN=${1:-zsh}
N=${N:-100}
PARALLEL=${PARALLEL:-8}

PLUGIN=$(realpath zsh-z.plugin.zsh)
TESTDIR=$(mktemp -d -t zshz-stress.XXXXXX)
trap 'rm -rf "$TESTDIR"' EXIT

export ZSHZ_DATA="$TESTDIR/.z"
# Default flock timeout (1s) is meant to keep a stuck holder from freezing
# the prompt; under heavy stress, give writers plenty of time to acquire so
# we measure real lock-correctness, not the timeout drop-rate.
export ZSHZ_LOCK_TIMEOUT=${ZSHZ_LOCK_TIMEOUT:-30}
TARGET="$TESTDIR/target"
mkdir -p "$TARGET"

echo "zsh:           $("$ZSH_BIN" --version)"
echo "writers:       $N"
echo "parallel:      $PARALLEL"
echo "lock timeout:  ${ZSHZ_LOCK_TIMEOUT}s"

seq 1 "$N" | xargs -P "$PARALLEL" -I{} \
  "$ZSH_BIN" -c "source '$PLUGIN'; zshz --add '$TARGET'"

rank=$(awk -F'|' -v p="$TARGET" '$1==p { print $2 }' "$ZSHZ_DATA")
echo "expected rank: $N"
echo "actual rank:   ${rank:-0}"
[[ "$rank" == "$N" ]] && echo "PASS" || { echo "FAIL: lost $((N - ${rank:-0})) updates"; exit 1; }  
