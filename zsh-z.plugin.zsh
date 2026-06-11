################################################################################
# Zsh-z - jump around with Zsh - A native Zsh version of z without awk, sort,
# date, or sed
#
# https://github.com/agkozak/zsh-z
#
# Copyright (c) 2018-2026 Alexandros Kozak
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# z (https://github.com/rupa/z) is copyright (c) 2009 rupa deadwyler and
# licensed under the WTFPL license, Version 2.
#
# Zsh-z maintains a jump-list of the directories you actually use.
#
# INSTALL:
#   * put something like this in your .zshrc:
#       source /path/to/zsh-z.plugin.zsh
#   * cd around for a while to build up the database
#
# USAGE:
#   * z foo       cd to the most frecent directory matching foo
#   * z foo bar   cd to the most frecent directory matching both foo and bar
#                   (e.g. /foo/bat/bar/quux)
#   * z -r foo    cd to the highest ranked directory matching foo
#   * z -t foo    cd to most recently accessed directory matching foo
#   * z -l foo    List matches instead of changing directories
#   * z -e foo    Echo the best match without changing directories
#   * z -c foo    Restrict matches to subdirectories of PWD
#   * z -x        Remove a directory (default: PWD) from the database
#   * z -xR       Remove a directory (default: PWD) and its subdirectories from
#                   the database
#
# ENVIRONMENT VARIABLES:
#
#   ZSHZ_CASE -> if `ignore', pattern matching is case-insensitive; if `smart',
#     pattern matching is case-insensitive only when the pattern is all
#     lowercase
#   ZSHZ_CD -> the directory-changing command that is used (default: builtin cd)
#   ZSHZ_CMD -> name of command (default: z)
#   ZSHZ_COMPLETION -> completion method (default: 'frecent'; 'legacy' for
#     alphabetic sorting)
#   ZSHZ_DATA -> name of datafile (default: ~/.z)
#   ZSHZ_EXCLUDE_DIRS -> array of directories to exclude from your database
#     (default: empty)
#   ZSHZ_KEEP_DIRS -> array of directories that should not be removed from the
#     database, even if they are not currently available (default: empty)
#   ZSHZ_LOCK_TIMEOUT -> seconds to wait for the lockfile before giving up
#     (default: 1)
#   ZSHZ_MAX_SCORE -> maximum combined score the database entries can have
#     before beginning to age (default: 9000)
#   ZSHZ_NO_RESOLVE_SYMLINKS -> '1' prevents symlink resolution
#   ZSHZ_OWNER -> your username (if you want use Zsh-z while using sudo -s)
#   ZSHZ_UNCOMMON -> if 1, do not jump to "common directories," but rather drop
#     subdirectories based on what the search string was (default: 0)
################################################################################

# Minimalistic solution to allow this plugin to keep running under sh/bash/ksh
# emulation while continuing to use Zsh-only syntax features
if [[ -o KSH_ARRAYS || -o SH_WORD_SPLIT ]]; then
  emulate zsh -c "source ${(%):-%N}"
  return $?
fi

autoload -Uz is-at-least

if ! is-at-least 4.3.11; then
  print "Zsh-z requires Zsh v4.3.11 or higher." >&2
  return 1 2> /dev/null || exit 1
fi

############################################################
# The help message
#
# Globals:
#   ZSHZ_CMD
############################################################
_zshz_usage() {
  print "Usage: ${ZSHZ_CMD:-${_Z_CMD:-z}} [OPTION]... [ARGUMENT]
Jump to a directory that you have visited frequently or recently, or a bit of both, based on the partial string ARGUMENT.

With no ARGUMENT, list the directory history in ascending rank.

  --add Add a directory to the database
  -c    Only match subdirectories of the current directory
  -e    Echo the best match without going to it
  -h    Display this help and exit
  -l    List all matches without going to them
  -r    Match by rank
  -t    Match by recent access
  -x    Remove a directory from the database (by default, the current directory)
  -xR   Remove a directory and its subdirectories from the database (by default, the current directory)" |
    fold -s -w $(( COLUMNS > 0 ? COLUMNS : 80 )) >&2
}

# Load zsh/datetime module, if necessary
(( ${+EPOCHSECONDS} )) || zmodload zsh/datetime

# Global associative array for internal use
typeset -gA ZSHZ

# Fallback utilities in case Zsh lacks zsh/files (as is the case with MobaXterm)
ZSHZ[CHMOD]='chmod'
ZSHZ[CHOWN]='chown'
ZSHZ[MV]='mv'
ZSHZ[RM]='rm'

# Try to load zsh/files. zf_chown, zf_mv, and zf_rm are usually present in Zsh
# 4.3.11. zf_chmod only became available in Zsh 5.0, so we load it separately
# below. If zsh/files is not available at all, we silently fall back to the
# external utilities chmod, chown, mv, and rm.
if [[ ${builtins[zf_chown]-} != 'defined' ||
      ${builtins[zf_mv]-}    != 'defined' ||
      ${builtins[zf_rm]-}    != 'defined' ]]; then
  zmodload -F zsh/files b:zf_chown b:zf_mv b:zf_rm &> /dev/null
fi

[[ ${builtins[zf_chmod]-} == 'defined' ]] ||
    zmodload -F zsh/files b:zf_chmod &> /dev/null

# Use zsh/files, if it is available.
[[ ${builtins[zf_chmod]-} == 'defined' ]] && ZSHZ[CHMOD]='zf_chmod'
[[ ${builtins[zf_chown]-} == 'defined' ]] && ZSHZ[CHOWN]='zf_chown'
[[ ${builtins[zf_mv]-} == 'defined' ]] && ZSHZ[MV]='zf_mv'
[[ ${builtins[zf_rm]-} == 'defined' ]] && ZSHZ[RM]='zf_rm'

# Load zsh/system, if necessary
[[ ${modules[zsh/system]-} == 'loaded' ]] || zmodload zsh/system &> /dev/null

# Make sure ZSHZ_EXCLUDE_DIRS has been declared so that other scripts can
# simply append to it
(( ${+ZSHZ_EXCLUDE_DIRS} )) || typeset -gUa ZSHZ_EXCLUDE_DIRS

# Determine if zsystem flock is available
zsystem supports flock &> /dev/null && ZSHZ[USE_FLOCK]=1

############################################################
# The Zsh-z Command
#
# Globals:
#   ZSHZ
#   ZSHZ_CASE
#   ZSHZ_CD
#   ZSHZ_COMPLETION
#   ZSHZ_DATA
#   ZSHZ_DEBUG
#   ZSHZ_EXCLUDE_DIRS
#   ZSHZ_KEEP_DIRS
#   ZSHZ_MAX_SCORE
#   ZSHZ_OWNER
#
# Arguments:
#   $* Command options and arguments
############################################################
zshz() {

  # Don't use `emulate -L zsh' - it breaks PUSHD_IGNORE_DUPS
  setopt LOCAL_OPTIONS NO_KSH_ARRAYS NO_SH_WORD_SPLIT EXTENDED_GLOB UNSET
  (( ZSHZ_DEBUG )) && setopt LOCAL_OPTIONS WARN_CREATE_GLOBAL

  local REPLY
  local -a lines

  # Allow the user to specify a custom datafile in $ZSHZ_DATA (or legacy $_Z_DATA)
  local custom_datafile="${ZSHZ_DATA:-$_Z_DATA}"

  # If a datafile was provided as a standalone file without a directory path
  # print a warning and exit
  if [[ -n ${custom_datafile} && ${custom_datafile} != */* ]]; then
    print "ERROR: You configured a custom Zsh-z datafile (${custom_datafile}), but have not specified its directory." >&2
    return 1
  fi

  # If the user specified a datafile, use that or default to ~/.z
  # If the datafile is a symlink, it gets dereferenced
  local datafile=${${custom_datafile:-$HOME/.z}:A}

  # If the datafile is a directory, print a warning and exit
  if [[ -d $datafile ]]; then
    print "ERROR: Zsh-z's datafile (${datafile}) is a directory." >&2
    return 1
  fi

  # Make sure that the datafile exists before attempting to read it or lock it
  # for writing. The file must end with 0600 permissions; ZSHZ[CHMOD] is
  # `zf_chmod' on Zsh 5+ and the external `chmod' otherwise.
  [[ -f $datafile ]] || {
    mkdir -p "${datafile:h}" && touch "$datafile" && ${ZSHZ[CHMOD]} 600 "$datafile"
    # When $ZSHZ_OWNER is set (e.g. under `sudo -s'), hand the freshly created
    # file off to that user immediately, so a query-only invocation can't leave
    # behind a root-owned .z that the normal-user shell can't read.
    local _owner=${ZSHZ_OWNER:-${_Z_OWNER}}
    [[ -n $_owner ]] && ${ZSHZ[CHOWN]} "${_owner}:$(id -ng "${_owner}")" "$datafile"
  }

  # Bail if we don't own the datafile and $ZSHZ_OWNER is not set
  [[ -z ${ZSHZ_OWNER:-${_Z_OWNER}} && -f $datafile && ! -O $datafile ]] &&
    return

  ############################################################
  # Add a path to or remove one from the datafile
  #
  # Globals:
  #   ZSHZ
  #   ZSHZ_EXCLUDE_DIRS
  #   ZSHZ_OWNER
  #
  # Arguments:
  #   $1 Which action to perform (--add/--remove)
  #   $2 The path to add
  ############################################################
  _zshz_add_or_remove_path() {
    local action=$1
    shift

    if [[ $action == '--add' ]]; then

      # These $HOME / $ZSHZ_EXCLUDE_DIRS guards mirror the ones in
      # _zshz_precmd, but they are not redundant: precmd filters $PWD as an
      # early-out (skip the background fork), whereas --add is now a public
      # entry point and must enforce the same policies as the precmd functin.
      #Keep both in sync.

      # Don't add $HOME
      [[ $* == $HOME ]] && return

      # Don't track directory trees excluded in $ZSHZ_EXCLUDE_DIRS
      local exclude
      for exclude in ${(@)ZSHZ_EXCLUDE_DIRS:-${(@)_Z_EXCLUDE_DIRS}}; do
        case $* in
          ${exclude}|${exclude}/*) return ;;
        esac
      done
    fi

    # Resolve the directory to be removed, and confirm a full-database wipe,
    # *before* taking the lock. Both are independent of the datafile, and the
    # confirmation is interactive: holding the lock across a `read -q' the user
    # might walk away from would make concurrent writers in other shells time
    # out on ZSHZ_LOCK_TIMEOUT and silently drop their adds while the prompt
    # sits open. A lock should wrap the read-modify-write, never a question.
    local xdir  # Directory to be removed
    if [[ $action == '--remove' ]]; then
      if (( ${ZSHZ_NO_RESOLVE_SYMLINKS:-${_Z_NO_RESOLVE_SYMLINKS}} )); then
        [[ -d ${${*:-${PWD}}:a} ]] && xdir=${${*:-${PWD}}:a}
      else
        [[ -d ${${*:-${PWD}}:A} ]] && xdir=${${*:-${PWD}}:A}
      fi

      if (( ${+opts[-R]} )) && [[ $xdir == '/' ]]; then
        if ! read -q "?Delete entire Zsh-z database? "; then
          print && return 1
        fi
      fi
    fi

    # A temporary file that gets copied over the datafile if all goes well
    local tempfile="${datafile}.${RANDOM}" lockfile="${datafile}.lock"
    integer lockfd=0

    {
      # Using zsystem flock
      if (( ZSHZ[USE_FLOCK] )); then

        # Obtain an exclusive lock on the lockfile.
        #
        # Locking the datafile directly would not actually serialize concurrent
        # writers, since the datafile gets replaced by mv and each new datafile
        # has a new inode -- so a separate, stable lockfile is needed.
        #
        # Bound the lock acquisition (default 1s, override with ZSHZ_LOCK_TIMEOUT)
        # so a stuck holder can't freeze precmd's foreground `zshz --add'. Once
        # the holder dies, the kernel frees the lock and the next add succeeds
        # automatically -- no manual `rm ~/.z.lock' needed.
        #
        # On timeout we return silently and on purpose: the precmd add is
        # best-effort and runs backgrounded (`&!'), so there is nowhere useful
        # to report to -- a message would land on the terminal asynchronously,
        # mid-keystroke, possibly every prompt. To diagnose a database that has
        # stopped updating, run a foreground `z --add .' and check `$?'; see
        # the README.
        [[ -f $lockfile ]] || touch "$lockfile"
        zsystem flock -t ${ZSHZ_LOCK_TIMEOUT:-1} -f lockfd "$lockfile" 2> /dev/null || return

      fi

      # Read the datafile only after obtaining the lock, so concurrent --add
      # calls don't all act on the same stale snapshot.
      lines=( ${(f)"$(< $datafile)"} )
      # Discard entries that are incomplete or incorrectly formatted
      lines=( ${(M)lines:#/*\|[[:digit:]]##[.,]#[[:digit:]]#\|[[:digit:]]##} )

      # Hold the fd in an *unset* scalar, not `integer tmpfd' (which seeds it
      # with 0). On some Zsh builds, `exec {tmpfd}>|...' refuses to clobber a
      # parameter already holding a number that names an open fd -- and 0 is
      # stdin, always open -- yielding "can't clobber parameter tmpfd
      # containing file descriptor 0". An empty scalar isn't a valid fd, so
      # the guard never fires. See https://github.com/agkozak/zsh-z/issues/81
      local tmpfd
      case $action in
        --add)
          # When zf_chmod isn't available (Zsh 4.3.11), avoid the
          # ~900us fork+execve of external /usr/bin/chmod on every
          # write. Create the tempfile with mode 0600 from the start
          # via `umask 077' inside a subshell -- the umask change is
          # contained to the forked child process and the OS prevents
          # it from leaking back to the parent. Subshell fork without
          # exec is ~50us, ~18x cheaper than the chmod fallback.
          if [[ ${ZSHZ[CHMOD]} == 'zf_chmod' ]]; then
            exec {tmpfd}>|"$tempfile"  # Open up tempfile for writing
            ${ZSHZ[CHMOD]} 600 "$tempfile"
            _zshz_update_datafile $tmpfd "$*"
          else
            ( umask 077
              exec {tmpfd}>|"$tempfile"
              _zshz_update_datafile $tmpfd "$*" )
          fi
          local ret=$?
          ;;
        --remove)
          # $xdir was resolved before the lock, and for `-xR /' the
          # whole-database wipe was already confirmed there.
          local -a lines_to_keep
          if (( ${+opts[-R]} )); then
            # All of the lines that don't match the directory to be deleted
            lines_to_keep=( ${lines:#${xdir}\|*} )
            # Or its subdirectories
            lines_to_keep=( ${lines_to_keep:#${xdir%/}/**} )
          else
            # All of the lines that don't match the directory to be deleted
            lines_to_keep=( ${lines:#${xdir}\|*} )
          fi
          if [[ $lines != "$lines_to_keep" ]]; then
            lines=( $lines_to_keep )
          else
            return 1  # The $PWD isn't in the datafile
          fi
          # Same umask-subshell pattern as --add: avoid the external
          # chmod when zf_chmod isn't available.
          if [[ ${ZSHZ[CHMOD]} == 'zf_chmod' ]]; then
            exec {tmpfd}>|"$tempfile"  # Open up tempfile for writing
            ${ZSHZ[CHMOD]} 600 "$tempfile"
            print -u $tmpfd -l -- $lines
          else
            ( umask 077; print -l -- $lines >| "$tempfile" )
          fi
          local ret=$?
          ;;
      esac

      if [[ -n $tmpfd ]]; then
        # Close tempfile
        exec {tmpfd}>&-
      fi

      if (( ret != 0 )); then
        # Avoid clobbering the datafile if the write to tempfile failed
        ${ZSHZ[RM]} -f "$tempfile"
        return $ret
      fi

      integer write_ret chown_ret
      local owner
      owner=${ZSHZ_OWNER:-${_Z_OWNER}}

      if (( ZSHZ[USE_FLOCK] )); then
        # An unusual case: if inside Docker container where datafile could be bind
        # mounted
        if [[ -f '/.dockerenv' || ( -r '/proc/1/cgroup' && "$(< '/proc/1/cgroup')" == *docker* ) ]]; then
          print -- "$(< "$tempfile")" >| "$datafile" 2> /dev/null
          write_ret=$?
          # Reassert 0600 permissions
          (( write_ret == 0 )) && ${ZSHZ[CHMOD]} 600 "$datafile" 2> /dev/null
          ${ZSHZ[RM]} -f "$tempfile" 2> /dev/null
        # All other cases
        else
          ${ZSHZ[MV]} "$tempfile" "$datafile" 2> /dev/null
          write_ret=$?
          (( write_ret != 0 )) && ${ZSHZ[RM]} -f "$tempfile" 2> /dev/null
        fi
        # Preserve the write failure itself; best-effort tempfile cleanup must not
        # turn a failed persist into a successful return.
        (( write_ret == 0 )) || return $write_ret

        if [[ -n $owner ]]; then
          # Chown the lockfile alongside the datafile: zsystem flock opens it
          # O_RDWR, so if root creates it first under sudo -s, the unprivileged
          # $ZSHZ_OWNER user's flock attempts would fail with EACCES (silently
          # swallowed), turning --add and -x into no-ops.
          ${ZSHZ[CHOWN]} "${owner}:$(id -ng "${owner}")" "$datafile" "$lockfile"
          chown_ret=$?
          # Surface post-write chown failures too: the current write landed, but a
          # wrong owner can break the next locked write.
          (( chown_ret == 0 )) || return $chown_ret
        fi
      else
        if [[ -n $owner ]]; then
          ${ZSHZ[CHOWN]} "${owner}:$(id -ng "${owner}")" "$tempfile"
          chown_ret=$?
          if (( chown_ret != 0 )); then
            # In the no-flock path, chown happens before the move, so clean up the
            # tempfile and leave the live database untouched.
            ${ZSHZ[RM]} -f "$tempfile" 2> /dev/null
            return $chown_ret
          fi
        fi
        ${ZSHZ[MV]} -f "$tempfile" "$datafile" 2> /dev/null
        write_ret=$?
        if (( write_ret != 0 )); then
          ${ZSHZ[RM]} -f "$tempfile" 2> /dev/null
          return $write_ret
        fi
      fi
    } always {
      # zsystem flock -f opens a real fd; explicitly unlock it so repeated
      # foreground precmd writes don't leak lock descriptors and stall peers.
      (( lockfd != 0 )) && zsystem flock -u $lockfd 2> /dev/null
    }

    # In order to make z -x work, we have to disable zsh-z's adding
    # to the database until the user changes directory and the
    # chpwd_functions are run
    if [[ $action == '--remove' ]]; then
      ZSHZ[DIRECTORY_REMOVED]=1
    fi
  }

  ############################################################
  # Read the current datafile contents, update them, "age" them
  # when the total rank gets high enough, and print the new
  # contents to STDOUT.
  #
  # Globals:
  #   ZSHZ_KEEP_DIRS
  #   ZSHZ_MAX_SCORE
  #
  # Arguments:
  #   $1 File descriptor linked to tempfile
  #   $2 Path to be added to datafile
  ############################################################
  _zshz_update_datafile() {

    integer fd=$1
    local -A rank time

    # Characters special to the shell (such as '[]') are quoted with backslashes
    # See https://github.com/rupa/z/issues/246
    local add_path=${(q)2}

    local now=$EPOCHSECONDS line dir
    local path_field rank_field time_field count x
    local -i keep

    rank[$add_path]=1
    time[$add_path]=$now

    for line in $lines; do
      path_field=${line%%\|*}

      # Filter non-existent paths (honoring ZSHZ_KEEP_DIRS) inline so
      # we walk $lines once instead of twice. The `keep=1; break' also
      # fixes a latent bug: the previous existence-check loop had no
      # `break' after appending, so a non-existent path matching
      # multiple ZSHZ_KEEP_DIRS patterns was processed more than once.
      if [[ ! -d $path_field ]]; then
        keep=0
        for dir in ${(@)ZSHZ_KEEP_DIRS}; do
          if [[ $path_field == ${dir}/* || $path_field == $dir || $dir == '/' ]]; then
            keep=1
            break
          fi
        done
        (( keep )) || continue
      fi

      # Quote in place: assoc-array keys need shell-special chars
      # backslash-escaped (rupa/z#246).
      path_field=${(q)path_field}
      rank_field=${${line%\|*}#*\|}
      time_field=${line##*\|}

      # When a rank drops below 1, drop the path from the database
      (( rank_field < 1 )) && continue

      if [[ $path_field == $add_path ]]; then
        rank[$path_field]=$rank_field
        (( rank[$path_field]++ ))
        time[$path_field]=$now
      else
        rank[$path_field]=$rank_field
        time[$path_field]=$time_field
      fi
      (( count += rank_field ))
    done
    local -a out
    if (( count > ${ZSHZ_MAX_SCORE:-${_Z_MAX_SCORE:-9000}} )); then
      # Aging
      for x in ${(k)rank}; do
        out+=( "$x|$(( 0.99 * rank[$x] ))|${time[$x]}" )
      done
    else
      for x in ${(k)rank}; do
        out+=( "$x|${rank[$x]}|${time[$x]}" )
      done
    fi
    print -u $fd -l -- $out || return 1
  }

  ############################################################
  # The original tab completion method
  #
  # String processing is smartcase -- case-insensitive if the
  # search string is lowercase, case-sensitive if there are
  # any uppercase letters. Spaces in the search string are
  # treated as *'s in globbing. Read the contents of the
  # datafile and print matches to STDOUT.
  #
  # Arguments:
  #   $1 The string to be completed
  ############################################################
  _zshz_legacy_complete() {

    local line path_field path_field_normalized

    # Replace spaces in the search string with asterisks for globbing
    1=${1//[[:space:]]/*}

    # Hoist loop-invariants out of the per-line loop -- $1 and
    # $ZSHZ_TRAILING_SLASH don't change inside the loop, so the
    # lowercase comparison and the trailing-slash branch were pure
    # waste when recomputed N times. `query_lower' lets the case-
    # insensitive branch glob against a precompiled lowercase pattern.
    local query_lower=${1:l}
    local -i is_lowercase_query=0
    [[ $1 == $query_lower ]] && is_lowercase_query=1
    local -i trail=${ZSHZ_TRAILING_SLASH:-0}

    for line in $lines; do

      path_field=${line%%\|*}

      path_field_normalized=$path_field
      (( trail )) && path_field_normalized=${path_field%/}/

      # If the search string is all lowercase, the search will be case-insensitive
      if (( is_lowercase_query )) && [[ ${path_field_normalized:l} == *${~query_lower}* ]]; then
        print -- $path_field
      # Otherwise, case-sensitive
      elif [[ $path_field_normalized == *${~1}* ]]; then
        print -- $path_field
      fi

    done
    # TODO: Search strings with spaces in them are currently treated case-
    # insensitively.
  }

  ############################################################
  # If matches share a common root, find it, and put it in
  # REPLY for _zshz_output to use.
  #
  # Arguments:
  #   $@ Candidate paths
  ############################################################
  _zshz_find_common_root() {
    local -a common_matches
    local x short

    common_matches=( "$@" )

    for x in ${(@)common_matches}; do
      if [[ -z $short ]] || (( $#x < $#short )) || [[ $x != ${short}/* ]]; then
        short=$x
      fi
    done

    [[ $short == '/' ]] && return

    for x in ${(@)common_matches}; do
      [[ $x != $short* ]] && return
    done

    REPLY=$short
  }

  ############################################################
  # Calculate a common root, if there is one. Then do one of
  # the following:
  #
  #   1) Print a list of completions in frecent order;
  #   2) List them (z -l) to STDOUT; or
  #   3) Put a common root or best match into REPLY
  #
  # Globals:
  #   ZSHZ_UNCOMMON
  #
  # Arguments:
  #   $1 Name of an associative array of matches and ranks
  #   $2 The best match or best case-insensitive match
  #   $3 Whether to produce a completion, a list, or a root or
  #        match
  ############################################################
  _zshz_output() {

    local match_array=$1 match=$2 format=$3
    local common x v
    local -a descending_list output

    _zshz_find_common_root ${(@Pk)match_array}
    common=$REPLY

    # Iterate the caller's matches/imatches array as flat key-value
    # pairs via ${(@Pkv)...} instead of copying into a local
    # associative array. Avoids the hash-table allocation and K
    # inserts that the copy required.
    local -a kv
    local -i i
    kv=( ${(@Pkv)match_array} )

    case $format in

      completion)
        # Build "rank|path" rows, then sort by leading numeric rank
        # (descending) and strip the rank+'|' prefix to keep paths. The
        # rank string is never user-visible -- `${...#*\|}' discards it
        # -- so the old `%.2f' formatting is dropped: `(@On)' parses the
        # leading number whether or not it has two decimal places.
        for ((i=1; i<=${#kv}; i+=2)); do
          descending_list+=( "${kv[i+1]}|${kv[i]}" )
        done
        descending_list=( ${${(@On)descending_list}#*\|} )
        print -l $descending_list
        ;;

      list)
        # The bare `z -l' fast path (no query) inlines an equivalent
        # formatting block straight on $lines to skip this pipeline --
        # keep the two list formatters in sync.
        local path_to_display
        for ((i=1; i<=${#kv}; i+=2)); do
          x=${kv[i]} v=${kv[i+1]}
          (( v )) || continue
          path_to_display=$x
          (( ZSHZ_TILDE )) &&
            path_to_display=${path_to_display/#${HOME}/\~}
          # Right-pad the integer rank to 10 chars so the line sorts
          # numerically by rank under `${(@on)output}'. Equivalent in
          # output shape to `printf "%-10d %s\n"' but stays in parameter
          # expansion. The `%.*' strip drops frecency's decimal tail
          # ("30000.0" -> "30000") to match what `%-10d' produced.
          output+=( "${(r:10:)${v%.*}} $path_to_display" )
        done
        if [[ -n $common ]]; then
          (( ZSHZ_TILDE )) && common=${common/#${HOME}/\~}
          (( $#output > 1 )) && printf "%-10s %s\n" 'common:' $common
        fi
        if (( $#output )); then
          # -lt: most-recent first (descending); -lr and default -l:
          # ascending rank.
          if (( $+opts[-t] )); then
            print -l -- ${(@On)output}
          else
            print -l -- ${(@on)output}
          fi
        fi
        ;;

      *)
        if (( ! ZSHZ_UNCOMMON )) && [[ -n $common ]]; then
          REPLY=$common
        else
          REPLY=${(P)match}
        fi
        ;;
    esac
  }

  ############################################################
  # Match a pattern by rank, time, or a combination of the
  # two, and output the results as completions, a list, or a
  # best match.
  #
  # Globals:
  #   ZSHZ
  #   ZSHZ_CASE
  #   ZSHZ_KEEP_DIRS
  #   ZSHZ_OWNER
  #
  # Arguments:
  #   #1 Pattern to match
  #   $2 Matching method (rank, time, or [default] frecency)
  #   $3 Output format (completion, list, or [default] store
  #     in REPLY
  ############################################################
  _zshz_find_matches() {
    setopt LOCAL_OPTIONS NO_EXTENDED_GLOB

    local fnd=$1 method=$2 format=$3

    local line dir path_field rank_field time_field rank dx
    local -A matches imatches
    local best_match ibest_match hi_rank=-9999999999 ihi_rank=-9999999999
    local -i keep

    # Hoist loop-invariants. $fnd, $1, and $ZSHZ_TRAILING_SLASH don't
    # change inside the per-line loop, so the space-to-glob
    # substitution, the `${1:l} == $1' check, and the `:l' on $q were
    # pure waste when recomputed N times. The `q_lower' precompute
    # lets `${~q_lower}' replace `${~q:l}' in the case-insensitive
    # branches: same expanded pattern, compiled once.
    local q=${fnd//[[:space:]]/\*}
    local q_lower=${q:l}
    local -i is_lowercase_query=0
    [[ ${1:l} == $1 ]] && is_lowercase_query=1
    local -i trail=${ZSHZ_TRAILING_SLASH:-0}
    local now=$EPOCHSECONDS

    for line in $lines; do
      path_field=${line%%\|*}

      # Filter non-existent paths (honoring ZSHZ_KEEP_DIRS) inline so we
      # walk $lines once instead of twice. The `keep=1; break' inside the
      # inner loop also fixes a latent bug: the previous existence-check
      # loop had no `break' after appending, so a non-existent path that
      # matched multiple ZSHZ_KEEP_DIRS patterns was processed more than
      # once.
      if [[ ! -d $path_field ]]; then
        keep=0
        for dir in ${(@)ZSHZ_KEEP_DIRS}; do
          if [[ $path_field == ${dir}/* || $path_field == $dir || $dir == '/' ]]; then
            keep=1
            break
          fi
        done
        (( keep )) || continue
      fi

      rank_field=${${line%\|*}#*\|}
      time_field=${line##*\|}

      case $method in
        rank) rank=$rank_field ;;
        time) (( rank = time_field - now )) ;;
        *)
          # Frecency routine: weight a path's stored frequency (rank_field)
          # by how recently it was visited (dx seconds ago). 10000 scales
          # the result into integer-comparable territory; the 3.75 / (...)
          # term decays from 3 (just now) toward 0 as dx grows, so older
          # paths lose rank. This is the canonical copy; the bare `z -l'
          # fast path inlines the same formula -- keep the two in sync.
          (( dx = now - time_field ))
          rank=$(( 10000 * rank_field * (3.75/( (0.0001 * dx + 1) + 0.25)) ))
          ;;
      esac

      local path_field_normalized=$path_field
      (( trail )) && path_field_normalized=${path_field%/}/

      # If $ZSHZ_CASE is 'ignore', be case-insensitive.
      #
      # If it's 'smart', be case-insensitive unless the string to be matched
      # includes capital letters.
      #
      # Otherwise, the default behavior of Zsh-z is to match case-sensitively if
      # possible, then to fall back on a case-insensitive match if possible.
      #
      # Track best_match / ibest_match directly from $rank in each branch so
      # we never have to math-subscript matches[] / imatches[] -- the math
      # parser interprets shell-special chars in associative-array keys as
      # syntax (rupa/z#246), and the workaround used to be a seven-char
      # escape pass on every line. Comparing the $rank scalar to the running
      # max sidesteps the subscript entirely.
      if [[ $ZSHZ_CASE == 'smart' ]] && (( is_lowercase_query )) &&
         [[ ${path_field_normalized:l} == ${~q_lower} ]]; then
        imatches[$path_field]=$rank
        if (( rank > ihi_rank )); then
          ibest_match=$path_field
          ihi_rank=$rank
          ZSHZ[CASE_INSENSITIVE]=1
        fi
      elif [[ $ZSHZ_CASE != 'ignore' && $path_field_normalized == ${~q} ]]; then
        matches[$path_field]=$rank
        if (( rank > hi_rank )); then
          best_match=$path_field
          hi_rank=$rank
        fi
      elif [[ $ZSHZ_CASE != 'smart' && ${path_field_normalized:l} == ${~q_lower} ]]; then
        imatches[$path_field]=$rank
        if (( rank > ihi_rank )); then
          ibest_match=$path_field
          ihi_rank=$rank
          ZSHZ[CASE_INSENSITIVE]=1
        fi
      fi
    done

    # Return 1 when there are no matches
    [[ -z $best_match && -z $ibest_match ]] && return 1

    if [[ -n $best_match ]]; then
      _zshz_output matches best_match $format
    elif [[ -n $ibest_match ]]; then
      _zshz_output imatches ibest_match $format
    fi
  }

  # THE MAIN ROUTINE

  local -A opts

  zparseopts -E -D -A opts -- \
    -add \
    -complete \
    c \
    e \
    h \
    -help \
    l \
    r \
    R \
    t \
    x

  if [[ $1 == '--' ]]; then
    shift
  elif [[ -n ${(M)@:#-*} && -z $compstate ]]; then
    print "Improper option(s) given."
    _zshz_usage
    return 1
  fi

  local opt output_format method='frecency' fnd prefix req

  for opt in ${(k)opts}; do
    case $opt in
      --add)
        # Don't change the database when invoked via --complete (e.g., from
        # tab completion).
        (( ${+opts[--complete]} )) && continue
        [[ ! -d $* ]] && return 1
        local dir
        # Cygwin and MSYS2 have a hard time with relative paths expressed from /
        if [[ $OSTYPE == (cygwin|msys) && $PWD == '/' && $* != /* ]]; then
          set -- "/$*"
        fi
        if (( ${ZSHZ_NO_RESOLVE_SYMLINKS:-${_Z_NO_RESOLVE_SYMLINKS}} )); then
          dir=${*:a}
        else
          dir=${*:A}
        fi
        _zshz_add_or_remove_path --add "$dir"
        return
        ;;
      --complete)
        if [[ -s $datafile && ${ZSHZ_COMPLETION:-frecent} == 'legacy' ]]; then
          lines=( ${(f)"$(< $datafile)"} )
          # Discard entries that are incomplete or incorrectly formatted
          lines=( ${(M)lines:#/*\|[[:digit:]]##[.,]#[[:digit:]]#\|[[:digit:]]##} )
          _zshz_legacy_complete "$1"
          return
        fi
        output_format='completion'
        ;;
      -c) [[ $* == ${PWD}/* || $PWD == '/' ]] || prefix="$PWD " ;;
      -h|--help)
        (( ${+opts[--complete]} )) && continue
        _zshz_usage
        return
        ;;
      -l) output_format='list' ;;
      -r) method='rank' ;;
      -t) method='time' ;;
      -x)
        (( ${+opts[--complete]} )) && continue
        # Cygwin and MSYS2 have a hard time with relative paths expressed from /
        if [[ $OSTYPE == (cygwin|msys) && $PWD == '/' && $* != /* ]]; then
          set -- "/$*"
        fi
        _zshz_add_or_remove_path --remove $*
        return
        ;;
    esac
  done

  # Load the datafile into an array and parse it
  lines=( ${(f)"$(< $datafile)"} )
  # Discard entries that are incomplete or incorrectly formatted
  lines=( ${(M)lines:#/*\|[[:digit:]]##[.,]#[[:digit:]]#\|[[:digit:]]##} )

  req="$*"
  fnd="$prefix$*"

  [[ -n $fnd && $fnd != "$PWD " ]] || {
    [[ $output_format != 'completion' ]] && output_format='list'
  }

  #########################################################
  # Allow the user to specify directory-changing command
  # using $ZSHZ_CD (default: builtin cd).
  #
  # Globals:
  #   ZSHZ_CD
  #
  # Arguments:
  #   $* Path
  #########################################################
  zshz_cd() {
    setopt LOCAL_OPTIONS NO_WARN_CREATE_GLOBAL

    if [[ -z $ZSHZ_CD ]]; then
      builtin cd "$*"
    else
      ${=ZSHZ_CD} "$*"
    fi
  }

  #########################################################
  # If $ZSHZ_ECHO == 1, display paths as you jump to them.
  # If it is also the case that $ZSHZ_TILDE == 1, display
  # the home directory as a tilde.
  #########################################################
  _zshz_echo() {
    if (( ZSHZ_ECHO )); then
      if (( ZSHZ_TILDE )); then
        print ${PWD/#${HOME}/\~}
      else
        print $PWD
      fi
    fi
  }

  if [[ ${@: -1} == /* ]] && (( ! $+opts[-e] && ! $+opts[-l] )); then
    # cd if possible; echo the new path if $ZSHZ_ECHO == 1
    [[ -d ${@: -1} ]] && zshz_cd ${@: -1} && _zshz_echo && return
  fi

  # Fast path: bare `zshz -l' (no query, list format). Skip the
  # `_zshz_find_matches' / `_zshz_output' pipeline -- there is nothing
  # to match against, no `matches[]'/`imatches[]' to maintain, no
  # case-mode branching, no `${(Pkv)...}' copy. Build the formatted
  # output array directly, then sort and print. Mirrors the list arm
  # of `_zshz_output' but operates straight on $lines.
  if [[ $output_format == 'list' && -z $fnd ]]; then
    local line path_field rank_field time_field rank dx path_to_display dir
    local common now=$EPOCHSECONDS
    local -a output paths
    local -i keep

    for line in $lines; do
      path_field=${line%%\|*}

      if [[ ! -d $path_field ]]; then
        keep=0
        for dir in ${(@)ZSHZ_KEEP_DIRS}; do
          if [[ $path_field == ${dir}/* || $path_field == $dir || $dir == '/' ]]; then
            keep=1
            break
          fi
        done
        (( keep )) || continue
      fi

      rank_field=${${line%\|*}#*\|}
      time_field=${line##*\|}
      case $method in
        rank) rank=$rank_field ;;
        time) (( rank = time_field - now )) ;;
        *)
          # Frecency routine -- see _zshz_find_matches for the canonical
          # copy and the constants' rationale; keep the two in sync.
          (( dx = now - time_field ))
          rank=$(( 10000 * rank_field * (3.75/( (0.0001 * dx + 1) + 0.25)) ))
          ;;
      esac
      (( rank )) || continue

      paths+=( $path_field )
      path_to_display=$path_field
      (( ZSHZ_TILDE )) && path_to_display=${path_to_display/#${HOME}/\~}
      output+=( "${(r:10:)${rank%.*}} $path_to_display" )
    done

    if (( $#paths )); then
      _zshz_find_common_root $paths
      common=$REPLY
      REPLY=
    fi

    if [[ -n $common ]]; then
      (( ZSHZ_TILDE )) && common=${common/#${HOME}/\~}
      (( $#output > 1 )) && printf "%-10s %s\n" 'common:' $common
    fi

    if (( $#output )); then
      if (( $+opts[-t] )); then
        print -l -- ${(@On)output}
      else
        print -l -- ${(@on)output}
      fi
      return 0
    fi
    return 1
  fi

  # With option -c, make sure query string matches beginning of matches;
  # otherwise look for matches anywhere in paths

  # The braces in ${+opts[-c]} keep the subscript inside parameter expansion,
  # where the math evaluator can never see `-c' as arithmetic -- zpm-zsh/colors
  # defines a global $c that a bare math subscript would pick up.
  if (( ${+opts[-c]} )); then
    _zshz_find_matches "$fnd*" $method $output_format
  else
    _zshz_find_matches "*$fnd*" $method $output_format
  fi

  local ret2=$?

  local cd
  cd=$REPLY

  # New experimental "uncommon" behavior
  #
  # If the best choice at this point is something like /foo/bar/foo/bar, and the
  # search pattern is `bar', go to /foo/bar/foo/bar; but if the search pattern
  # is `foo', go to /foo/bar/foo
  if (( ZSHZ_UNCOMMON )) && [[ -n $cd ]]; then
    if [[ -n $cd ]]; then

      # In the search pattern, replace spaces with *
      local q=${fnd//[[:space:]]/\*}
      q=${q%/} # Trailing slash has to be removed

      # As long as the best match is not case-insensitive
      if (( ! ZSHZ[CASE_INSENSITIVE] )); then
        # Count the number of characters in $cd that $q matches
        local q_chars=$(( ${#cd} - ${#${cd//${~q}/}} ))
        # Try dropping directory elements from the right; stop when it affects
        # how many times the search pattern appears
        until (( ( ${#cd:h} - ${#${${cd:h}//${~q}/}} ) != q_chars )); do
          cd=${cd:h}
        done

      # If the best match is case-insensitive
      else
        local q_chars=$(( ${#cd} - ${#${${cd:l}//${~${q:l}}/}} ))
        until (( ( ${#cd:h} - ${#${${${cd:h}:l}//${~${q:l}}/}} ) != q_chars )); do
          cd=${cd:h}
        done
      fi

      ZSHZ[CASE_INSENSITIVE]=0
    fi
  fi

  if (( ret2 == 0 )) && [[ -n $cd ]]; then
    if (( $+opts[-e] )); then               # echo
      (( ZSHZ_TILDE )) && cd=${cd/#${HOME}/\~}
      print -- "$cd"
    else
      # cd if possible; echo the new path if $ZSHZ_ECHO == 1
      [[ -d $cd ]] && zshz_cd "$cd" && _zshz_echo
    fi
  else
    # if $req is a valid path, cd to it; echo the new path if $ZSHZ_ECHO == 1
    if ! (( $+opts[-e] || $+opts[-l] )) && [[ -d $req ]]; then
      zshz_cd "$req" && _zshz_echo
    else
      return $ret2
    fi
  fi
}

alias ${ZSHZ_CMD:-${_Z_CMD:-z}}='zshz 2>&1'

############################################################
# precmd - add path to datafile unless `z -x' has just been
#   run
#
# Globals:
#   ZSHZ
############################################################
_zshz_precmd() {
  # Protect against `setopt NO_UNSET'
  setopt LOCAL_OPTIONS UNSET

  # Do not add PWD to datafile when in HOME directory, or
  # if `z -x' has just been run
  [[ $PWD == "$HOME" ]] || (( ZSHZ[DIRECTORY_REMOVED] )) && return

  # Don't track directory trees excluded in ZSHZ_EXCLUDE_DIRS
  local exclude
  for exclude in ${(@)ZSHZ_EXCLUDE_DIRS:-${(@)_Z_EXCLUDE_DIRS}}; do
    case $PWD in
      ${exclude}|${exclude}/*) return ;;
    esac
  done

  # Add PWD to the datafile. Background the write so the prompt doesn't wait on
  # read + tempfile + rename + chown -- which is tens of ms per prompt on
  # 9P-bridged or VHD-backed paths. Backgrounding is safe under develop's
  # lock design: the `always { zsystem flock -u $lockfd }' block in
  # _zshz_add_or_remove_path guarantees the parent never holds an open
  # lockfd between precmd invocations (so a `&!' fork can't inherit one),
  # and ZSHZ_LOCK_TIMEOUT (default 1s) bounds contention so a stuck holder
  # can't pile up writers. `&!' is zsh background + disown: no wrapper
  # subshell, no job-table entry, no "Done" line at the next prompt.
  zshz --add "$PWD" &!

  # See https://github.com/rupa/z/pull/247/commits/081406117ea42ccb8d159f7630cfc7658db054b6
  : $RANDOM
}

############################################################
# chpwd
#
# When the $PWD is removed from the datafile with `z -x',
# Zsh-z refrains from adding it again until the user has
# left the directory.
#
# Globals:
#   ZSHZ
############################################################
_zshz_chpwd() {
  ZSHZ[DIRECTORY_REMOVED]=0
}

autoload -Uz add-zsh-hook

add-zsh-hook precmd _zshz_precmd
add-zsh-hook chpwd _zshz_chpwd

############################################################
# Completion
############################################################

# Standardized $0 handling
# https://zdharma-continuum.github.io/Zsh-100-Commits-Club/Zsh-Plugin-Standard.html
0="${${ZERO:-${0:#${ZSH_ARGZERO-}}}:-${(%):-%N}}"
0="${${(M)0:#/*}:-$PWD/$0}"

(( ${fpath[(ie)${0:A:h}]} <= ${#fpath} )) || fpath=( "${0:A:h}" "${fpath[@]}" )

# Save the existing Tab binding so that the completion widget can invoke it,
# but being careful not to create a situation where the widget ends up calling
# itself and causing infinite recursion if this script is re-sourced.
if (( ! ${+widgets[_zshz_zle_completion_widget]} )); then
  ZSHZ[TAB_BINDING]="${$(bindkey -M main '^I')##* }"
fi

############################################################
# ZLE widget to fix spaces-as-wildcards completion
#
# When completing a Zsh-z command with multiple search terms
# (e.g. `z us lo bi'), collapse the terms into a single
# wildcard-joined word (e.g. `z us*lo*bi') before triggering
# completion. This causes compadd to replace the whole query
# with the matched path rather than just the last word.
#
# Globals:
#   ZSHZ_CMD
############################################################
_zshz_zle_completion_widget() {

  setopt LOCAL_OPTIONS EXTENDED_GLOB NO_KSH_ARRAYS NO_SH_WORD_SPLIT

  local cmd=${ZSHZ_CMD:-${_Z_CMD:-z}}

  # Ensure tab completion works under `setopt COMPLETE_ALIASES'. Under that
  # option zsh looks up `_comps[$cmd]' verbatim rather than expanding the
  # alias to `zshz' first; compinit's static `#compdef' tag in `_zshz' is
  # parsed literally (no parameter expansion) and only covers the literal
  # `zshz' command. Run once -- the guard short-circuits on subsequent Tabs.
  (( ${+_comps[$cmd]} )) || compdef _zshz $cmd 2> /dev/null

  # If a trailing space was added after an already-completed absolute path
  # (e.g. `z /usr/local/bin '), a second Tab would otherwise re-trigger
  # completion on an empty word and insert a duplicate. Bail out early.
  if [[ $LBUFFER[-1] == ' ' && ${${LBUFFER% }##* } == [/~]* ]]; then
    return
  fi

  # Only act when there are at least two words after the command
  if [[ $LBUFFER == ${cmd}\ *\ * ]]; then
    local after=${LBUFFER#${cmd} }
    local -a parts option_parts search_parts
    local p past_options=0

    parts=( ${(z)after} )
    for p in $parts; do
      if (( ! past_options )) && [[ $p == (--|-[cehlrRtx]##|--add|--complete|--help) ]]; then
        option_parts+=( $p )
        # `--' terminates option parsing; subsequent tokens are positional,
        # even if they happen to look like options.
        [[ $p == -- ]] && past_options=1
      else
        past_options=1
        search_parts+=( $p )
      fi
    done

    if (( ${#search_parts} > 1 )); then
      LBUFFER="${cmd}${option_parts:+ ${(j: :)option_parts}} ${(j:*:)search_parts}"
    fi
  fi

  # If Tab had a non-default binding, continue to use it; otherwise the default
  # expand-or-complete gets used.
  zle ${ZSHZ[TAB_BINDING]:-expand-or-complete}
}

# Register the widget and bind to Tab, but only if this script has not already
# been sourced -- avoid infinite recursion.
if (( ! ${+widgets[_zshz_zle_completion_widget]} )); then
  zle -N _zshz_zle_completion_widget
  bindkey -M main '^I' _zshz_zle_completion_widget
fi

############################################################
# zsh-z functions
############################################################
ZSHZ[FUNCTIONS]='_zshz_usage
                 _zshz_add_or_remove_path
                 _zshz_update_datafile
                 _zshz_legacy_complete
                 _zshz_find_common_root
                 _zshz_output
                 _zshz_find_matches
                 zshz
                 _zshz_precmd
                 _zshz_chpwd
                 _zshz
                 _zshz_zle_completion_widget'

############################################################
# Enable WARN_NESTED_VAR for functions listed in
#   ZSHZ[FUNCTIONS]
############################################################
(( ${+ZSHZ_DEBUG} )) && () {
  if is-at-least 5.4.0; then
    local x
    for x in ${=ZSHZ[FUNCTIONS]}; do
      functions -W $x
    done
  fi
}

############################################################
# Unload function
#
# See https://github.com/agkozak/Zsh-100-Commits-Club/blob/master/Zsh-Plugin-Standard.adoc#unload-fun
#
# Globals:
#   ZSHZ
#   ZSHZ_CMD
############################################################
zsh-z_plugin_unload() {
  emulate -L zsh

  add-zsh-hook -D precmd _zshz_precmd
  add-zsh-hook -d chpwd _zshz_chpwd

  zle -D _zshz_zle_completion_widget

  # Only restore Tab binding if it is still bound to our widget; otherwise
  # leave it alone.
  local _zshz_current_tab
  _zshz_current_tab="$(bindkey -M main '^I' 2>/dev/null || true)"
  if [[ ${_zshz_current_tab##* } == _zshz_zle_completion_widget ]]; then
    bindkey -M main '^I' "${ZSHZ[TAB_BINDING]:-expand-or-complete}"
  fi

  local x
  for x in ${=ZSHZ[FUNCTIONS]}; do
    (( ${+functions[$x]} )) && unfunction $x
  done

  unset ZSHZ

  fpath=( "${(@)fpath:#${0:A:h}}" )

  (( ${+aliases[${ZSHZ_CMD:-${_Z_CMD:-z}}]} )) &&
    unalias ${ZSHZ_CMD:-${_Z_CMD:-z}}

  unfunction $0
}

# vim: fdm=indent:ts=2:et:sts=2:sw=2:
