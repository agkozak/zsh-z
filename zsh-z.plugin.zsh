# synopsis {{{
# ZSH-z - jump around with ZSH - A native ZSH version of z without awk, sort,
# date, or sed
#
# https://github.com/agkozak/zsh-z
# }}}
#
# Copyright (c) 2018-2020 Alexandros Kozak
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
#     ZSHZ_MAX_SCORE -> maximum combined score the database entries can have before beginning to age (default: 9000)
#     ZSHZ_NO_RESOLVE_SYMLINKS -> '1' prevents symlink resolution
#     ZSHZ_EXCLUDE_DIRS -> array of directories to exclude from your database
#     ZSHZ_OWNER -> your username (if you want use ZSH-z while using sudo -s) }}}
#
# vim: fdm=indent:ts=2:et:sts=2:sw=2:

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

# Load zsh/datetime module, if necessary
(( $+EPOCHSECONDS )) || zmodload zsh/datetime

# Load zsh/system, if necessary
[[ ${modules[zsh/system]} == 'loaded' ]] || zmodload zsh/system &> /dev/null

# Load zsh/files, if necessary
[[ ${builtins[zf_chown]} == 'defined' ]] \
  && [[ ${builtins[zf_mv]} == 'defined' ]] \
  && [[ ${builtins[zf_rm]} == 'defined' ]] \
  || zmodload -F zsh/files b:zf_chown b:zf_mv b:zf_rm

# Global associative array for internal use
typeset -gA ZSHZ

# Determine whether zsystem flock is available
zsystem supports flock &> /dev/null && ZSHZ[USE_FLOCK]=1

############################################################
# Add a path to the datafile
#
# Arguments:
#   $1 Path to be added
############################################################
_zshz_add_path() {

  local datafile=${ZSHZ_DATA:-${_Z_DATA:-${HOME}/.z}}

  # $HOME isn't worth matching
  [[ $* == "$HOME" ]] && return

  # Don't track directory trees excluded in ZSHZ_EXCLUDE_DIRS
  local exclude
  for exclude in ${(@)ZSHZ_EXCLUDE_DIRS:-${(@)_Z_EXCLUDE_DIRS}}; do
    case $* in
      $exclude*) return ;;
    esac
  done

  # A temporary file that gets copied over the datafile if all goes well
  local tempfile="${datafile}.${RANDOM}"

  # See https://github.com/rupa/z/pull/199/commits/ed6eeed9b70d27c1582e3dd050e72ebfe246341c
  if (( ZSHZ[USE_FLOCK] )); then

    # Make sure that the datafile exists for locking
    [[ -f $datafile ]] || touch "$datafile"
    local lockfd

    # Grab exclusive lock (released when function exits)
    if (( ZSHZ_DEBUG )); then
      zsystem flock -f lockfd "$datafile" || return
    else
      zsystem flock -f lockfd "$datafile" 2> /dev/null || return
    fi

    _zshz_update_datafile "$*" >| "$tempfile"
    zf_mv "$tempfile" "$datafile" \
      || zf_rm -f "$tempfile"

    if [[ -n ${ZSHZ_OWNER:-${_Z_OWNER}} ]]; then
      zf_chown ${ZSHZ_OWNER:-${_Z_OWNER}}:"$(id -ng ${ZSHZ_OWNER:_${_Z_OWNER}})" \
        "$datafile"
    fi

  else

    _zshz_update_datafile "$*" >| "$tempfile"
    local ret=$?

    # Avoid clobbering the datafile in a race condition
    if (( ret != 0 )) && [[ -f $datafile ]]; then
      zf_rm -f "$tempfile"
    else
      if [[ -n ${ZSHZ_OWNER:-${_Z_OWNER}} ]]; then
        zf_chown "${ZSHZ_OWNER:-${_Z_OWNER}}":"$(id -ng "${ZSHZ_OWNER:-${_Z_OWNER}}")" \
          "$tempfile"
      fi
      zf_mv -f "$tempfile" "$datafile" 2> /dev/null \
        || zf_rm -f "$tempfile"
    fi
  fi
}

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
  local add_path=${(q)1}

  local -a lines existing_paths
  local now=$EPOCHSECONDS line
  local datafile=${ZSHZ_DATA:-${_Z_DATA:-${HOME}/.z}}
  local path_field rank_field time_field count x

  rank[$add_path]=1
  time[$add_path]=$now

  # Load the datafile into an array
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
  if (( count > ${ZSHZ_MAX_SCORE:-${_Z_MAX_SCORE:-9000}} )); then
    # Aging
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
  setopt LOCAL_OPTIONS EXTENDED_GLOB

  local line path_field
  local datafile=${ZSHZ_DATA:-${_Z_DATA:-${HOME}/.z}}
  local -a lines

  # Replace spaces in the search string with asterisks for globbing
  1=${1// ##/*}

  lines=( ${(f)"$(< $datafile)"} ) 2> /dev/null

  for line in $lines; do

    path_field=${line%%\|*}

    # If the search string is all lowercase, the search will be case-insensitive
    if [[ $1 == "${1:l}" ]] && [[ ${path_field:l} == *${~1}* ]]; then
        print -- $path_field
    # Otherwise, case-sensitive
    elif [[ $path_field == *${~1}* ]]; then
      print -- $path_field
    fi

  done
  # TODO: Search strings with spaces in them are currently treated case-
  # insensitively.
}

############################################################
# Remove path from datafile
#
# Arguments:
#   $1 Path to be removed
############################################################
_zshz_remove_path() {
  setopt LOCAL_OPTIONS EXTENDED_GLOB

  local datafile=${ZSHZ_DATA:-${_Z_DATA:-${HOME}/.z}}

  if (( ZSHZ[USE_FLOCK] )); then
    [[ -f $datafile ]] || touch $datafile
    local lockfd
    zsystem flock -f lockfd $datafile 2> /dev/null || return
  fi

  local -a lines lines_to_keep
  lines=( ${(f)"$(<$datafile)"} )
  # All of the lines that don't match the directory to be deleted
  lines_to_keep=( ${lines:#${PWD}\|*} )
  if [[ $lines != "$lines_to_keep" ]]; then
    lines=( $lines_to_keep )
  else
    return 1  # The $PWD isn't in the datafile
  fi

  local tempfile="${datafile}.${RANDOM}"
  print -l -- $lines > "$tempfile"
  zf_mv -f "$tempfile" "$datafile" \
    || zf_rm -f "$tempfile"

  if [[ -n ${ZSHZ_OWNER:-${_Z_OWNER}} ]]; then
    zf_chown ${ZSHZ_OWNER:-${_Z_OWNER}}:"$(id -ng ${ZSHZ_OWNER:_${_Z_OWNER}})" \
      "$datafile"
  fi

  # In order to make z -x work, we have to disable zsh-z's adding
  # to the database until the user changes directory and the
  # chpwd_functions are run
  ZSHZ[DIRECTORY_REMOVED]=1
}

############################################################
# If matches share a common root, find it, and put it on the
# editing buffer stack for _zshz_output to use.
#
# Arguments:
#   $1 Name of associative array of matches and ranks
############################################################
_zshz_find_common_root() {
  local -a common_matches
  local x short

  common_matches=( ${(Pk)1[@]} )

  for x in ${common_matches[@]}; do
    if [[ -z $short ]] || (( $#x < $#short )); then
      short=$x
    fi
  done

  [[ $short == '/' ]] && return

  for x in ${common_matches[@]}; do
    [[ $x != $short* ]] && return
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
#   $3 Whether to produce a completion, a list, or a root or
#        match
############################################################
_zshz_output() {
  setopt LOCAL_OPTIONS EXTENDED_GLOB

  local match_array=$1 match=$2 format=$3
  local common stack k x
  local -A output_matches
  local -a descending_list output

  output_matches=( ${(Pkv)match_array} )

  _zshz_find_common_root $match_array
  read -rz common

  case $format in

    completion)
      for k in ${(@k)output_matches}; do
        print -z -f "%.2f|%s" ${output_matches[$k]} $k
        read -rz stack
        descending_list+=( $stack )
      done
      descending_list=( ${${(@On)descending_list}#*\|} )
      print -l $descending_list
      ;;

    list)
      for x in ${(k)output_matches}; do
        if (( output_matches[$x] )); then
          # Always use period as decimal separator for compatibility with fzf-z
          LC_ALL=C print -z -f "%-10.2f %s\n" ${output_matches[$x]} $x
          read -rz stack
          output+=( $stack )
        fi
      done
      if [[ -n $common ]]; then
        (( $#output > 1 )) && printf "%-10s %s\n" 'common:' $common
      fi
      # Sort results and remove trailing ".00"
      for x in ${(@on)output};do
        print "${${x%${x##[[:digit:]]##[[:punct:]][[:digit:]]##[[:blank:]]}}/[[:punct:]]00/   }${x##[[:digit:]]##[[:punct:]][[:digit:]]##[[:blank:]]}"
      done
      ;;

    *)
      if (( ! ZSHZ_UNCOMMON )) && [[ -n $common ]]; then
        print -z -- $common
      else
        print -z -- ${(P)match}
      fi
      ;;
  esac
}

############################################################
# Load the datafile, and match a pattern by rank, time, or a
# combination of the two, and output the results as
# completions, a list, or a best match.
#
# Arguments:
#   #1 Pattern to match
#   $2 Matching method (rank, time, or [default] frecency)
#   $3 Output format (completion, list, or [default] print
#   to editing buffer stack)
############################################################
_zshz_find_matches() {
  setopt LOCAL_OPTIONS EXTENDED_GLOB

  local fnd=$1 method=$2 format=$3

  # Allow the user to specify the datafile name in $ZSHZ_DATA (default: ~/.z)
  local datafile=${ZSHZ_DATA:-${_Z_DATA:-${HOME}/.z}}

  # If datafile is a symlink, dereference it
  [[ -h $datafile ]] && datafile=${datafile:A}

  # Bail if we don't own the datafile and $ZSHZ_OWNER is not set
  [[ -z ${ZSHZ_OWNER:-${_Z_OWNER}} ]] && [[ -f $datafile ]] \
    && [[ ! -O $datafile ]] && return

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

    case $method in
      rank) rank=$rank_field ;;
      time) (( rank = time_field - EPOCHSECONDS )) ;;
      *)
        # Frecency routine
        (( dx = EPOCHSECONDS - time_field ))
        rank=$(( rank_field * (3.75/(0.0001 * dx + 1) + 0.25) ))
        ;;
    esac

    # Use spaces as wildcards
    local q=${fnd// ##/*}

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
      ZSHZ[CASE_INSENSITIVE]=1
    fi
  done

  # Return 1 when there are no matches
  [[ -z $best_match ]] && [[ -z $ibest_match ]] && return 1

  if [[ -n $best_match ]]; then
    _zshz_output matches best_match $format
  elif [[ -n $ibest_match ]]; then
    _zshz_output imatches ibest_match $format
  fi
}

############################################################
# The ZSH-z Command
#
# Arguments:
#   $* Command options and arguments
############################################################
zshz() {
  emulate -L zsh
  setopt LOCAL_OPTIONS EXTENDED_GLOB
  (( ZSHZ_DEBUG )) && setopt LOCAL_OPTIONS WARN_CREATE_GLOBAL

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

  if [[ $1 == '--' ]]; then
    shift
  elif [[ -n ${(M)@:#-*} ]] && [[ -z $compstate ]]; then
    print "Improper option(s) given."
    _zshz_usage
    return 1
  fi

  local opt output_format method='frecency' fnd

  for opt in ${(k)opts}; do
    case $opt in
      --add)
        _zshz_add_path "$*"
        return
        ;;
      --complete)
        if [[ -s $datafile ]] \
          && [[ ${ZSHZ_COMPLETION:-frecent} == 'legacy' ]]; then
          _zshz_legacy_complete "$1"
          return
        fi
        output_format='completion'
        ;;
      -c) [[ $* == ${PWD}/* ]] || [[ $PWD == '/' ]] || set -- "$PWD $*" ;;
      -h|--help)
        _zshz_usage
        return
        ;;
      -l) output_format='list' ;;
      -r) method='rank' ;;
      -t) method='time' ;;
      -x)
        _zshz_remove_path "$*"
        return
        ;;
    esac
  done
  fnd="$*"

  [[ -n $fnd ]] && [[ $fnd != "$PWD " ]] || {
    [[ $output_format != 'completion' ]] && output_format='list'
  }

  if [[ ${@: -1} == /* ]] && (( ! $+opts[-e] )) && (( ! $+opts[-l] )); then
    [[ -d ${@: -1} ]] && builtin cd ${@: -1} && return
  fi

  # With option -c, make sure query string matches beginning of matches;
  # otherwise look for matches anywhere in paths

  # zpm-zsh/colors has a global $c, so we'll avoid math expressions here
  if [[ ! -z ${(tP)opts[-c]} ]]; then
    _zshz_find_matches "$fnd*" $method $output_format
  else
    _zshz_find_matches "*$fnd*" $method $output_format
  fi

  local ret2=$?

  local cd
  read -rz cd


  # New experimental "uncommon" behavior
  #
  # If the best choice at this point is something like /foo/bar/foo/bar, and the  # search pattern is `bar', go to /foo/bar/foo/bar; but if the search pattern
  # is `foo', go to /foo/bar/foo
  if (( ZSHZ_UNCOMMON )) && [[ -n $cd ]]; then
    if [[ -n $cd ]]; then

      # In the search pattern, replace spaces with *
      local q=${fnd// ##/*}

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
      print -- "$cd"
    else
      builtin cd "$cd"
    fi
  else
    return $ret2
  fi
}

alias ${ZSHZ_CMD:-${_Z_CMD:-z}}='zshz 2>&1'

############################################################
# precmd and chpwd
############################################################

if (( ${ZSHZ_NO_RESOLVE_SYMLINKS:-${_Z_NO_RESOLVE_SYMLINKS}} )); then
  _zshz_precmd() {
    (( ! ZSHZ[DIRECTORY_REMOVED] )) && (zshz --add "${PWD:a}" &)
    # See https://github.com/rupa/z/pull/247/commits/081406117ea42ccb8d159f7630cfc7658db054b6
    : $RANDOM
  }
else
  # Add the $PWD to the datafile, unless $ZSHZ[directory removed] shows it to have been
  # recently removed with z -x
  _zshz_precmd() {
    (( ! ZSHZ[DIRECTORY_REMOVED] )) && (zshz --add "${PWD:A}" &)
    : $RANDOM
  }
fi

############################################################
# When the $PWD is removed from the datafile with z -x,
# ZSH-z refrains from adding it again until the user has
# left the directory.
############################################################
_zshz_chpwd() {
  ZSHZ[DIRECTORY_REMOVED]=0
}

autoload -U add-zsh-hook

add-zsh-hook precmd _zshz_precmd
add-zsh-hook chpwd _zshz_chpwd

############################################################
# Completion
############################################################

# Standarized $0 handling
# (See https://github.com/zdharma/Zsh-100-Commits-Club/blob/master/Zsh-Plugin-Standard.adoc)
0=${${ZERO:-${0:#$ZSH_ARGZERO}}:-${(%):-%N}}
0=${${(M)0:#/*}:-$PWD/$0}

fpath=( ${0:A:h} $fpath )

############################################################
# zsh-z functions
############################################################
ZSHZ[FUNCTIONS]='_zshz_usage
                _zshz_add_path
                _zshz_update_datafile
                _zshz_legacy_complete
                _zshz_remove_path
                _zshz_find_common_root
                _zshz_output
                _zshz_find_matches
                zshz
                _zshz_precmd
                _zshz_chpwd
                _zshz'

############################################################
# Enable WARN_NESTED_VAR for zsh-z chpwd_functions
############################################################
(( ZSHZ_DEBUG )) && () {
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
# See https://github.com/zdharma/Zsh-100-Commits-Club/blob/master/Zsh-Plugin-Standard.adoc#unload-fun
############################################################
zsh-z_plugin_unload() {
  emulate -L zsh

  add-zsh-hook -D precmd _zshz_precmd
  add-zsh-hook -d chpwd _zshz_chpwd

  local x
  for x in ${=ZSHZ[FUNCTIONS]}; do
    (( ${+functions[$x]} )) && unfunction $x
  done

  unset ZSHZ

  fpath=("${(@)fpath:#${0:A:h}}")

  alias ${ZSHZ_CMD:-${_Z_CMD:-z}} &> /dev/null \
    && unalias ${ZSHZ_CMD:-${_Z_CMD:-z}}

  unfunction $0
}
