# ZSH-z - jump around with ZSH - A native ZSH version of z without awk, sort,
# date, or sed
#
# https://github.com/agkozak/zsh-z
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
#     * optionally:
#       * Set ZSHZ_CMD in your .zshrc to change the command (default z)
#       * Set ZSHZ_COMPLETION to 'legacy' to restore the simpler, alphabetic
#           completion sorting method
#       * Set ZSHZ_DATA in your .zshrc to change the datafile (default ~/.z)
#       * Set ZSHZ_NO_RESOLVE_SYMLINKS to prevent symlink resolution
#       * Set ZSHZ_EXCLUDE_DIRS to an array of directories to exclude from your
#           database
#       * Set ZSHZ_OWNER to your username if you want use ZSH-z while sudoing
#           with $HOME kept
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

# shellcheck shell=ksh
# shellcheck disable=SC2016,SC2079,SC2086,SC2128

typeset -g USAGE="Usage: ${ZSHZ_CMD:-${_Z_CMD:-z}} [OPTION]... [ARGUMENT]
Jump to a directory that you have visited frequently or recently, or a bit of both, based on the partial string ARGUMENT.

With no ARGUMENT, list the directory history in ascending rank.

  -c    Only match subdirectories of the current directory
  -e    Echo the best match without going to it
  -h    Display this help and exit
  -l    List all matches without going to them
  -r    Match by rank
  -t    Match by recent access
  -x    Remove the current directory from the database"

# If the datafile is a directory, print a warning
[[ -d ${ZSHZ_DATA:-${_Z_DATA:-${HOME}/.z}} ]] && {
  print "ERROR: ZSH-z's datafile (${ZSHZ_DATA:-${_Z_DATA:-${HOME}/.z}}) is a directory." >&2
}

# Load zsh/datetime module, if necessary (only necessary on some old versions
# of ZSH
(( $+EPOCHSECONDS )) || zmodload zsh/datetime

########################################################
# Maintain the datafile
#
# Reads the old datafile contents from STDIN, adds the
# current path to them, alters the contents to "age"
# them, and prints the new contents of the datafile to
# STDOUT.
#
# Arguments:
#   $1 Path to be added to datafile
########################################################
_zshz_maintain_datafile() {
  # Characters special to the shell are quoted with backslashes
  # shellcheck disable=SC2154
  local add_path=${(q)1}
  local now=$EPOCHSECONDS count x line
  local datafile=${ZSHZ_DATA:-${_Z_DATA:-${HOME}/.z}}
  local -a lines
  local -A rank time

  rank[$add_path]=1
  time[$add_path]=$now

  # Load the datafile into an aray and parse it
  lines=( ${(f)"$(< $datafile)"} ) 2> /dev/null

  # Remove paths from database if they no longer exist
  local -a existing_paths
  for line in $lines; do
    [[ -d ${line%%\|*} ]] && existing_paths+=( $line )
  done
  lines=( $existing_paths )

  local path_field rank_field time_field
  for line in $lines; do
    path_field=${line%%\|*}
    rank_field=${${line%\|*}#*\|}
    time_field=${line##*\|}

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
      # When a rank drops below 1, drop the path from the database
      if (( (( 0.99 * rank[$x] )) >= 1 )); then
        print "$x|$(( 0.99 * rank[$x] ))|${time[$x]}"
      fi
    done
  else
    for x in ${(k)rank}; do
      print "$x|${rank[$x]}|${time[$x]}"
    done
  fi
}

########################################################
# Simple, legacy tab completion
#
# Process the query string for tab completion. Read the
# contents of the datafile from STDIN and prints matches
# to STDOUT.
#
# Arguments:
#   $1 The string to be completed
########################################################
_zshz_legacy_complete() {
  setopt LOCAL_OPTIONS EXTENDED_GLOB

  local imatch path_field rank_field time_field
  datafile=${ZSHZ_DATA:-${_Z_DATA:-${HOME}/.z}}

  # shellcheck disable=SC2053
  [[ $1 == ${1:l} ]] && imatch=1
  1=${1// ##/*}

  while IFS='|' read -r path_field rank_field time_field;  do
    if (( imatch )); then
      # shellcheck disable=SC2086,SC2154
      if [[ ${path_field:l} == *${~1}* ]]; then
        print $path_field
      fi
    elif [[ $path_field == *${~1}* ]]; then
      print $path_field
    fi
  done < "$datafile"
}

########################################################
# Find the common root of a list of matches, if it
# exists, and put it on the editor stack buffer
#
# Arguments:
#   $1 Name of associative array of matches and ranks
########################################################
_zshz_common() {
  local -A common_matches
  common_matches=( ${(Pkv)1} )
  local x short

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

  print -z $short
}

########################################################
# Put the desired directory on the editor stack buffer,
# or list it to STDOUT.
#
# Arguments:
#   $1 Associative array of matches and ranks
#   $2 best_match or ibest_match
#   $3 Whether or not to just print the results as a
#     list (0 or 1)
########################################################
_zshz_output() {
  # shellcheck disable=SC2034
  local common x match_array=$1 match=$2 list=${3:-0}
  local -a output
  local -A output_matches
  output_matches=( ${(Pkv)match_array} )

  _zshz_common $match_array
  read -rz common

  local stack
  if (( frecent_completion )); then
    local -a descending_list
    local k
    # shellcheck disable=SC2154
    for k in ${(@k)output_matches}; do
      print -z -f "%.2f|%s" ${output_matches[$k]} $k
      read -rz stack
      descending_list+=$stack
    done
    descending_list=( ${${(@On)descending_list}#*\|} )
    print -l $descending_list
  elif (( list )); then
    for x in ${(k)output_matches}; do
      if (( ${output_matches[$x]} )); then
        print -z -f "%-10.2f %s\n" ${output_matches[$x]} $x
        read -rz stack
        output+=$stack
      fi
    done
    if [[ -n $common ]]; then
      printf "%-10s %s\n" 'common:' $common
    fi
    # Sort results and remove trailing ".00"
    # shellcheck disable=SC2154
    for x in ${(@on)output};do
      print "${${x%${x##[[:digit:]]##\.[[:digit:]]##[[:blank:]]}}/\.00/   }${x##[[:digit:]]##\.[[:digit:]]##[[:blank:]]}"
    done
  else
    if [[ -n $common ]]; then
      print -z $common
    else
      # shellcheck disable=SC2154
      print -z ${(P)match}
    fi
  fi
}

############################################################
# THE COMMAND
#
# Arguments:
#   $* The command line arguments
############################################################
zshz() {
  setopt LOCAL_OPTIONS EXTENDED_GLOB

  (( ZSHZ_DEBUG )) && setopt WARN_CREATE_GLOBAL WARN_NESTED_VAR 2> /dev/null

  # Allow the user to specify the datafile name in $ZSHZ_DATA (default: ~/.z)
  local datafile=${ZSHZ_DATA:-${_Z_DATA:-${HOME}/.z}}

  # If datafile is a symlink, dereference it
  [[ -h $datafile ]] && datafile=${datafile:A}

  # Bail if we don't own the datafile and $ZSHZ_OWNER is not set
  [[ -z ${ZSHZ_OWNER:-${_Z_OWNER}} ]] && [[ -f $datafile ]] \
    && [[ ! -O $datafile ]] && return

  # Add entries to the datafile
  if [[ $1 == "--add" ]]; then
    shift

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
    local tempfile="$datafile.$RANDOM"

    _zshz_maintain_datafile "$*" >| "$tempfile"

    # Avoid clobbering the datafile in a race condition
    if (( $? != 0 )) && [[ -f $datafile ]]; then
      command rm -f "$tempfile"
    else
      if [[ -n ${ZSHZ_OWNER:-${_Z_OWNER}} ]]; then
        chown "${ZSHZ_OWNER:-${_Z_OWNER}}":"$(id -ng "${ZSHZ_OWNER:-${_Z_OWNER}}")" "$tempfile"
      fi
      command mv -f "$tempfile" "$datafile" 2> /dev/null \
        || command rm -f "$tempfile"
    fi

  elif [[ ${ZSHZ_COMPLETION:-frecent} == 'legacy' ]] && [[ $1 == '--complete' ]] \
    && [[ -s $datafile ]]; then

    _zshz_legacy_complete "$2"

  else
    # list/go
    local frecent_completion echo fnd last opt list typ
    while [[ -n $1 ]]; do
      case $1 in
        # The new frecent completion method returns directories in the order of
        # most frecent to least frecent
        --complete) [[ ${ZSHZ_COMPLETION:-frecent} != 'legacy' ]] \
          && frecent_completion=1 ;;
        --)
          while [[ -n $1 ]]; do
            shift
            fnd="$fnd${fnd:+ }$1"
          done
          ;;
        -*)
          opt=${1:1}
          while [[ -n $opt ]]; do
            case ${opt:0:1} in
              c) fnd="^$PWD $fnd" ;;
              e) echo=1 ;;
              h|-help) print $USAGE >&2; return ;;
              l) list=1 ;;
              r) typ='rank' ;;
              t) typ='recent' ;;
              x)
                local -a lines
                local line
                local tempfile="${datafile}.${RANDOM}"
                lines=( "${(@f)"$(<$datafile)"}" )
                # All of the lines that don't match the PWD
                lines=( ${(M)lines:#^${PWD}\|*} )
                print -l $lines > "$tempfile"
                command mv -f "$tempfile" "$datafile" \
                  || command rm -f "$tempfile"
                # In order to make z -x work, we have to disable zsh-z's adding
                # to the database until the user changes directory and the
                # chpwd_functions are run
                typeset -g ZSHZ_REMOVED=1
                return 0
                ;;
            esac
            opt=${opt:1}
          done
          ;;
        *) fnd="$fnd${fnd:+ }$1" ;;
      esac
      last=$1
      (( $# )) && shift
    done
    [[ -n $fnd ]] && [[ "$fnd" != "^$PWD " ]] || list=1

    # If we hit enter on a completion just go there
    case $last in
      # Completions will always start with /
      /*) (( ! list )) && [[ -d $last ]] && builtin cd "$last" && return ;;
    esac

    # If there is no datafile yet
    [[ -f $datafile ]] || return

    # shellcheck disable=SC2034
    local q=${${fnd// ##/*}#\^} hi_rank=-9999999999 ihi_rank=-9999999999 dx
    local best_match ibest_match rank line
    local -A matches imatches
    local -a lines existing_paths

    # Load the datafile into an aray and parse it
    lines=( ${(f)"$(< $datafile)"} )

    # Remove paths from database if they no longer exist
    for line in $lines; do
      [[ -d ${line%%\|*} ]] && existing_paths+=( $line )
    done
    lines=( $existing_paths )

    local path_field rank_field time_field
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

      # shellcheck disable=SC2154
      if [[ $path_field == *${~q}* ]]; then
        matches[$path_field]=$rank
      elif [[ ${path_field:l} == *${~q:l}* ]]; then
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

    if [[ -n $best_match ]]; then
      _zshz_output matches best_match $list
    elif [[ -n $ibest_match ]]; then
      _zshz_output imatches ibest_match $list
    fi

    local success=$?

    local cd
    read -rz cd

    if (( success == 0 )) && [[ -n $cd ]]; then
      if (( echo )); then
        print "$cd"
      else
        # shellcheck disable=SC2164
        builtin cd "$cd"
      fi
    else
      return 1
    fi
  fi
}

# shellcheck disable=SC2086,SC2139
alias ${ZSHZ_CMD:-${_Z_CMD:-z}}='zshz 2>&1'

############################################################
# precmd and chpwd
############################################################

# Add the PWD to the datafile, unless ZSHZ_REMOVED shows it to
# have been recently removed with z -x

if [[ -n ${ZSHZ_NO_RESOLVE_SYMLINKS:-${_Z_NO_RESOLVE_SYMLINKS}} ]]; then
  _zshz_precmd() {
    (( ! ZSHZ_REMOVED )) && (zshz --add "${PWD:a}" &)
  }
else
  _zshz_precmd() {
    (( ! ZSHZ_REMOVED )) && (zshz --add "${PWD:A}" &)
  }
fi

_zshz_chpwd() {
  typeset -g ZSHZ_REMOVED=0
}

# Be careful not to load the precmd and chpwd functions
# more than once

[[ -n "${precmd_functions[(r)_zshz_precmd]}" ]] || {
  precmd_functions[$(($#precmd_functions+1))]=_zshz_precmd
}

[[ -n "${chpwd_functions[(r)_zshz_chpwd]}" ]] || {
  chpwd_functions[$(($#chpwd_functions+1))]=_zshz_chpwd
}

############################################################
# COMPLETION
############################################################

# Load compinit only if it has not already been loaded
# shellcheck disable=SC2154
(( $+functions[compinit] )) || autoload -U compinit && compinit

############################################################
# The completion handler
############################################################
_zshz() {
  if [[ ${ZSHZ_COMPLETION} == 'legacy' ]]; then
    # shellcheck disable=SC2154
    compadd -x 'Completing directory' -U "${(f)"$(zshz --complete "$PREFIX")"}"
  else
    # shellcheck disable=SC2154
    compadd -x 'Completing directory' -U -V zsh-z "${(f)$(zshz --complete "$PREFIX")}"
  fi

  # shellcheck disable=SC2034,SC2154
  compstate[insert]=menu
}

compdef _zshz zshz

# vim: ts=2:et:sts=2:sw=2:
