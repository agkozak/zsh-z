# synopsis {{{
# ZSH-z - jump around with ZSH - A native ZSH version of z without awk, sort,
# date, or sed
#
# https://github.com/agkozak/zsh-z
# }}}
#
# Copyright (c) 2018 Alexandros Kozak
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
# ZSH-z maintains a jump-list of the directories you actually use.
#
# INSTALL:
#     * put something like this in your .zshrc:
#         source /path/to/zsh-z.plugin.zsh
#     * cd around for a while to build up the database
#
# USAGE:
#     * z foo     # cd to the most frecent directory matching foo
#     * z foo bar # cd to the most frecent directory matching both foo and bar
#                     (e.g. /foo/bat/bar/quux)
#     * z -r foo  # cd to the highest ranked directory matching foo
#     * z -t foo  # cd to most recently accessed directory matching foo
#     * z -l foo  # List matches instead of changing directories
#     * z -e foo  # Echo the best match without changing directories
#     * z -c foo  # Restrict matches to subdirectories of PWD
#     * z -x foo  # Remove the PWD from the database
#
# ENVIRONMENT VARIABLES:
#
# env-vars {{{
#     ZSHZ_CMD -> name of command (default: z)
#     ZSHZ_COMPLETION -> completion method (default: 'frecent'; 'legacy' for alphabetic sorting)
#     ZSHZ_DATA -> name of datafile (default: ~/.z)
#     ZSHZ_NO_RESOLVE_SYMLINKS -> '1' prevents symlink resolution
#     ZSHZ_EXCLUDE_DIRS -> array of directories to exclude from your database
#     ZSHZ_OWNER -> your username (if you want use ZSH-z while using sudo -s) }}}
#
# vim: fdm=indent:ts=2:et:sts=2:sw=2:
# shellcheck shell=ksh
# shellcheck disable=SC2016,SC2079,SC2086,SC2128

autoload -U is-at-least

if ! is-at-least 4.3.11; then
  print "ZSH-z requires ZSH v4.3.11 or higher." >&2 && exit
fi

############################################################
# The help message
############################################################
_zshz_usage() {
  print "Usage: ${ZSHZ_CMD:-${_Z_CMD:-z}} [OPTION]... [ARGUMENT]
Jump to a directory that you have visited frequently or recently, or a bit of both, based on the partial string ARGUMENT.

With no ARGUMENT, list the directory history in ascending rank.

  -c    Only match subdirectories of the current directory
  -e    Echo the best match without going to it
  -h    Display this help and exit
  -l    List all matches without going to them
  -r    Match by rank
  -t    Match by recent access
  -x    Remove the current directory from the database" >&2
}

# If the datafile is a directory, print a warning
[[ -d ${ZSHZ_DATA:-${_Z_DATA:-${HOME}/.z}} ]] && {
  print "ERROR: ZSH-z's datafile (${ZSHZ_DATA:-${_Z_DATA:-${HOME}/.z}}) is a directory." >&2
}

# Load zsh/datetime module, if necessary (only necessary on some old versions
# of ZSH
(( $+EPOCHSECONDS )) || zmodload zsh/datetime

# Load zsh/system, if necessary
whence -w zsystem &> /dev/null || zmodload zsh/system &> /dev/null

# Global associative array for internal use
typeset -gA ZSHZ

# Determine whether zsystem flock is available
if zsystem supports flock &> /dev/null; then
  ZSHZ[use_flock]=1
fi

############################################################
# Read the curent datafile contents, update them, "age" them
# when the total rank gets high enough, and print the new
# contents to STDOUT.
#
# Arguments:
#   $1 Path to be added to datafile
############################################################
_zshz_update_datafile() {
  local -A rank time

  # Characters special to the shell (such as '[]') are quoted with backslashes
  # See https://github.com/rupa/z/issues/246
  # shellcheck disable=SC2154
  local add_path=${(q)1}

  local -a lines existing_paths
  local now=$EPOCHSECONDS line
  local datafile=${ZSHZ_DATA:-${_Z_DATA:-${HOME}/.z}}
  local path_field rank_field time_field count x

  rank[$add_path]=1
  time[$add_path]=$now

  # Load the datafile into an array and parse it
  lines=( ${(f)"$(< $datafile)"} ) 2> /dev/null

  # Remove paths from database if they no longer exist
  for line in $lines; do
    [[ -d ${line%%\|*} ]] && existing_paths+=( $line )
  done
  lines=( $existing_paths )

  for line in $lines; do
    path_field=${line%%\|*}
    rank_field=${${line%\|*}#*\|}
    time_field=${line##*\|}

    # When a rank drops below 1, drop the path from the database
    (( rank_field < 1 )) && continue

    if [[ $path_field == "$1" ]]; then
      rank[$path_field]=$(( rank_field + 1 ))
      time[$path_field]=$now
    else
      rank[$path_field]=$(( rank_field ))
      time[$path_field]=$(( time_field ))
    fi
    (( count += rank_field ))
  done
  if (( count > 9000 )); then
    # Aging
    #
    # shellcheck disable=SC2154
    for x in ${(k)rank}; do
      print -- "$x|$(( 0.99 * rank[$x] ))|${time[$x]}"
    done
  else
    for x in ${(k)rank}; do
      print -- "$x|${rank[$x]}|${time[$x]}"
    done
  fi
}

############################################################
# The original tab completion method
#
# Process a string for tab completion. Read the contents of
# the datafile and print matches to STDOUT.
#
# Arguments:
#   $1 The string to be completed
############################################################
_zshz_legacy_complete() {
  setopt LOCAL_OPTIONS EXTENDED_GLOB

  local imatch line path_field
  local datafile=${ZSHZ_DATA:-${_Z_DATA:-${HOME}/.z}}
  local -a lines

  # shellcheck disable=SC2053
  [[ $1 == ${1:l} ]] && imatch=1
  1=${1// ##/*}

  # Load the datafile into an array and parse it
  lines=( ${(f)"$(< $datafile)"} ) 2> /dev/null

  for line in $lines; do
    path_field=${line%%\|*}
    if (( imatch )); then
      # shellcheck disable=SC2086,SC2154
      if [[ ${path_field:l} == *${~1}* ]]; then
        print -- $path_field
      fi
    elif [[ $path_field == *${~1}* ]]; then
      print -- $path_field
    fi
  done
}

############################################################
# If matches share a common root, find it, and put it on the
# editing buffer stack for _zshz_output to use.
#
# Arguments:
#   $1 Name of associative array of matches and ranks
############################################################
_zshz_common() {
  local -A common_matches
  local x short

  common_matches=( ${(Pkv)1} )

  # shellcheck disable=SC2154
  for x in ${(k)common_matches}; do
    if (( ${common_matches[$x]} )); then
      if [[ -z $short ]] || (( ${#x} < ${#short} )); then
        short=$x
      fi
    fi
  done

  [[ $short == '/' ]] && return

  for x in ${(k)common_matches}; do
    (( ${common_matches[$x]} )) && [[ $x != $short* ]] && return
  done

  print -z -- $short
}

############################################################
# Fetch the common root path from the editing buffer stack.
# Then either
#
#   1) Print a list of completions in frecent order;
#   2) List them (z -l) to STDOUT; or
#   3) Put a common root or best match onto the editing
#     buffer stack.
#
# Arguments:
#   $1 Name of an associative array of matches and ranks
#   $2 The best match or best case-insensitive match
#   $3 Whether or not to just print the results as a
#     list (0 or 1)
############################################################
_zshz_output() {
  # shellcheck disable=SC2034
  local match_array=$1 match=$2 list=${3:-0}
  local common stack k x
  local -A output_matches
  local -a descending_list output

  output_matches=( ${(Pkv)match_array} )

  _zshz_common $match_array
  read -rz common

  if (( frecent_completion )); then
    # shellcheck disable=SC2154
    for k in ${(@k)output_matches}; do
      print -z -f "%.2f|%s" ${output_matches[$k]} $k
      read -rz stack
      descending_list+=$stack
    done
    descending_list=( ${${(@On)descending_list}#*\|} )
    print -l $descending_list
  elif (( list )); then
    # shellcheck disable=SC2154
    for x in ${(k)output_matches}; do
      if (( ${output_matches[$x]} )); then
        print -z -f "%-10.2f %s\n" ${output_matches[$x]} $x
        read -rz stack
        output+=$stack
      fi
    done
    if [[ -n $common ]]; then
      (( ${#output} > 1 )) && printf "%-10s %s\n" 'common:' $common
    fi
    # Sort results and remove trailing ".00"
    # shellcheck disable=SC2154
    for x in ${(@on)output};do
      print "${${x%${x##[[:digit:]]##\.[[:digit:]]##[[:blank:]]}}/\.00/   }${x##[[:digit:]]##\.[[:digit:]]##[[:blank:]]}"
    done
  else
    if [[ -n $common ]]; then
      print -z -- $common
    else
      # shellcheck disable=SC2154
      print -z -- ${(P)match}
    fi
  fi
}

############################################################
# The ZSH-z Command
#
# Arguments:
#   $* The command line arguments
############################################################
zshz() {
  setopt LOCAL_OPTIONS EXTENDED_GLOB

  (( ZSHZ_DEBUG )) && setopt WARN_CREATE_GLOBAL WARN_NESTED_VAR 2> /dev/null

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
    t \
    x

  # Allow the user to specify the datafile name in $ZSHZ_DATA (default: ~/.z)
  local datafile=${ZSHZ_DATA:-${_Z_DATA:-${HOME}/.z}}

  # If datafile is a symlink, dereference it
  [[ -h $datafile ]] && datafile=${datafile:A}

  # Bail if we don't own the datafile and $ZSHZ_OWNER is not set
  [[ -z ${ZSHZ_OWNER:-${_Z_OWNER}} ]] && [[ -f $datafile ]] \
    && [[ ! -O $datafile ]] && return

  # Add entries to the datafile
  if (( $+opts[--add] )); then

    # $HOME isn't worth matching
    [[ $* == "$HOME" ]] && return

    # Don't track directory trees excluded in ZSHZ_EXCLUDE_DIRS
    local exclude
    for exclude in ${(@)ZSHZ_EXCLUDE_DIRS:-${(@)_Z_EXCLUDE_DIRS}}; do
      case $* in
        $exclude*) return ;;
      esac
    done

    # See https://github.com/rupa/z/pull/199/commits/ed6eeed9b70d27c1582e3dd050e72ebfe246341c
    if (( ZSHZ[use_flock] )); then

      # Make sure that the datafile exists for locking
      [[ -f $datafile ]] || touch "$datafile"
      local lockfd

      # Grab exclusive lock (released when function exits)
      if (( ZSHZ_DEBUG )); then
        zsystem flock -f lockfd "$datafile" || return
      else
        zsystem flock -f lockfd "$datafile" 2> /dev/null || return
      fi

      if [[ -n ${ZSHZ_OWNER:-${_Z_OWNER}} ]]; then
        chown ${ZSHZ_OWNER:-${_Z_OWNER}}:"$(id -ng ${ZSHZ_OWNER:_${_Z_OWNER}})" "$datafile"
      fi

      # =() process substitution serves as a tempfile
      print -- "$(< =(_zshz_update_datafile "$*"))" >| "$datafile" || return

    else

      # A temporary file that gets copied over the datafile if all goes well
      local tempfile="${datafile}.${RANDOM}"

      _zshz_update_datafile "$*" >| "$tempfile"
      local ret=$?

      # Avoid clobbering the datafile in a race condition
      if (( ret != 0 )) && [[ -f $datafile ]]; then
        command rm -f "$tempfile"
      else
        if [[ -n ${ZSHZ_OWNER:-${_Z_OWNER}} ]]; then
          chown "${ZSHZ_OWNER:-${_Z_OWNER}}":"$(id -ng "${ZSHZ_OWNER:-${_Z_OWNER}}")" "$tempfile"
        fi
        command mv -f "$tempfile" "$datafile" 2> /dev/null \
          || command rm -f "$tempfile"
      fi
    fi

  elif [[ ${ZSHZ_COMPLETION:-frecent} == 'legacy' ]] && (( $+opts[--complete] )) \
    && [[ -s $datafile ]]; then

    _zshz_legacy_complete "$1"

  else
    # Frecent completion, echo/list, help, and cd to match
    local current echo fnd frecent_completion last opt list typ

    for opt in ${(k)opts}; do
      case $opt in
        --complete)
          if [[ ${ZSHZ_COMPLETION:-frecent} != 'legacy' ]]; then
            frecent_completion=1
          fi
          ;;
        -c) set -- "$PWD $*" ;;
        -e) echo=1 ;;
        -h|--help) _zshz_usage; return ;;
        -l) list=1 ;;
        -r) typ='rank' ;;
        -t) typ='recent' ;;
        -x)
          # TODO: Take $ZSHZ_OWNER into account?

          if (( ZSHZ[use_flock] )); then
            [[ -f $datafile ]] || touch $datafile
            local lockfd
            zsystem flock -f lockfd $datafile 2> /dev/null || return
          fi

          local -a lines lines_to_keep
          lines=( "${(@f)"$(<$datafile)"}" )
          # All of the lines that don't match the directory to be deleted
          lines_to_keep=( ${(M)lines:#^${PWD}\|*} )
          if [[ $lines != "$lines_to_keep" ]]; then
            lines=( $lines_to_keep )
          else
            return 1  # The $PWD isn't in the datafile
          fi

          if (( ZSHZ[use_flock] )); then
            # =() process substitution serves as the tempfile
            print -- "$(< =(print -l $lines))" >| $datafile || return
          else
            local tempfile="${datafile}.${RANDOM}"
            print -l -- $lines > "$tempfile"
            command mv -f "$tempfile" "$datafile" \
              || command rm -f "$tempfile"
          fi

          # In order to make z -x work, we have to disable zsh-z's adding
          # to the database until the user changes directory and the
          # chpwd_functions are run
          ZSHZ[directory_removed]=1

          return
          ;;
      esac
    done
    fnd="$*"

    [[ -n $fnd ]] && [[ $fnd != "$PWD " ]] || list=1

    # If we hit enter on a completion just go there
    case $last in
      # Completions will always start with /
      /*) (( ! list )) && [[ -d $last ]] && builtin cd "$last" && return ;;
    esac

    # If there is no datafile yet
    # https://github.com/rupa/z/pull/256
    [[ -f $datafile ]] || return

    local -a lines existing_paths
    local line path_field rank_field time_field rank dx
    local -A matches imatches
    local best_match ibest_match hi_rank=-9999999999 ihi_rank=-9999999999

    # Load the datafile into an array and parse it
    lines=( ${(f)"$(< $datafile)"} )

    # Remove paths from database if they no longer exist
    for line in $lines; do
      [[ -d ${line%%\|*} ]] && existing_paths+=( $line )
    done
    lines=( $existing_paths )

    for line in $lines; do
      path_field=${line%%\|*}
      rank_field=${${line%\|*}#*\|}
      time_field=${line##*\|}

      case $typ in
        rank) rank=$rank_field ;;
        recent) (( rank = time_field - EPOCHSECONDS )) ;;
        # Frecency routine
        *)
          (( dx = EPOCHSECONDS - time_field ))
          if (( dx < 3600 )); then
            (( rank = rank_field * 4 ))
          elif (( dx < 86400 )); then
            (( rank = rank_field * 2 ))
          elif (( dx < 604800 )); then
            (( rank = rank_field / 2. ))
          else
            (( rank = rank_field / 4. ))
          fi
          ;;
      esac

      # Pattern matching is different when the -c option is on
      # shellcheck disable=SC2034
      local q=${fnd// ##/*}
      if (( current )); then
        q="$q*"
      else
        q="*$q*"
      fi

      # shellcheck disable=SC2154
      if [[ $path_field == ${~q} ]]; then
        matches[$path_field]=$rank
      elif [[ ${path_field:l} == ${~q:l} ]]; then
        imatches[$path_field]=$rank
      fi

      if (( matches[$path_field] )) \
        && (( matches[$path_field] > hi_rank )); then
        best_match=$path_field
        hi_rank=${matches[$path_field]}
      elif (( imatches[$path_field] )) \
        && (( imatches[$path_field] > ihi_rank )); then
        ibest_match=$path_field
        ihi_rank=${imatches[$path_field]}
      fi
    done

    # Return 1 when there are no matches
    [[ -z $best_match ]] && [[ -z $ibest_match ]] && return 1

    if [[ -n $best_match ]]; then
      _zshz_output matches best_match $list
    elif [[ -n $ibest_match ]]; then
      _zshz_output imatches ibest_match $list
    fi

    local ret2=$?

    local cd
    read -rz cd

    if (( ret2 == 0 )) && [[ -n $cd ]]; then
      if (( echo )); then
        print -- "$cd"
      else
        # shellcheck disable=SC2164
        builtin cd "$cd"
      fi
    else
      return $ret2
    fi
  fi
}

# shellcheck disable=SC2086,SC2139
alias ${ZSHZ_CMD:-${_Z_CMD:-z}}='zshz 2>&1'

############################################################
# precmd and chpwd
############################################################

if [[ -n ${ZSHZ_NO_RESOLVE_SYMLINKS:-${_Z_NO_RESOLVE_SYMLINKS}} ]]; then
  _zshz_precmd() {
    (( ! ZSHZ[directory_removed] )) && (zshz --add "${PWD:a}" &)
    # See https://github.com/rupa/z/pull/247/commits/081406117ea42ccb8d159f7630cfc7658db054b6
    : $RANDOM
  }
else
  # Add the $PWD to the datafile, unless $ZSHZ[directory removed] shows it to have been
  # recently removed with z -x
  _zshz_precmd() {
    (( ! ZSHZ[directory_removed] )) && (zshz --add "${PWD:A}" &)
    : $RANDOM
  }
fi

############################################################
# When the $PWD is removed from the datafile with z -x,
# ZSH-z refrains from adding it again until the user has
# left the directory.
############################################################
_zshz_chpwd() {
  ZSHZ[directory_removed]=0
}

autoload -U add-zsh-hook

add-zsh-hook precmd _zshz_precmd
add-zsh-hook chpwd _zshz_chpwd

############################################################
# Completion
############################################################

# Standarized $0 handling
# (See https://github.com/zdharma/Zsh-100-Commits-Club/blob/master/Zsh-Plugin-Standard.adoc)
0="${${ZERO:-${0:#$ZSH_ARGZERO}}:-${(%):-%N}}"
fpath=( ${0:A:h} $fpath )
