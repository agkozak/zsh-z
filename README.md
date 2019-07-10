# ZSH-z

[![MIT License](img/mit_license.svg)](https://opensource.org/licenses/MIT)
![ZSH version 4.3.11 and higher](img/zsh_4.3.11_plus.svg)
[![GitHub stars](https://img.shields.io/github/stars/agkozak/zsh-z.svg)](https://github.com/agkozak/zsh-z/stargazers)

![ZSH-z demo](img/demo.gif)

ZSH-z is a command line tool that allows you to jump quickly to directories that you have visited frequently in the past, or recently -- but most often a combination of the two (a concept known as ["frecency"](https://en.wikipedia.org/wiki/Frecency)). It works by keeping track of when you go to directories and how much time you spend in them. It is then in the position to guess where you want to go when you type a partial string, e.g. `z src` might take you to `~/src/zsh`. `z zsh` might also get you there, and `z c/z` might prove to be even more specific -- it all depends on your habits and how much time you have been using ZSH-z to build up a database. After using ZSH-z for a little while, you will get to where you want to be by typing considerably less than you would need if you were using `cd`.

ZSH-z is a native ZSH port of [rupa/z](https://github.com/rupa/z), a tool written for `bash` and ZSH that uses embedded `awk` scripts to do the heavy lifting. It has been quite possibly my most used command line tool for a couple of years. I decided to translate it, `awk` parts and all, into pure ZSH script, to see if by eliminating calls to external tools (`awk`, `sort`, `date`, and `sed`) and reducing forking through subshells I could make it faster. Initial testing has been satisfying: ZSH-z is highly responsive, and the main database maintenance routine (triggered by `precmd_functions`) is considerably more efficient on Linux, BSD, and Solaris installations, and even more so on MSYS2 and Cygwin, which are notoriously slow at forking.

ZSH-z is a drop-in replacement for `rupa/z` and will, by default, use the same database (`~/.z`), so you can go on using `rupa/z` if you launch `bash`. That said, there are a few improvements (see below), including the new default behavior of sorting your tab completions by frecency rather than just letting ZSH sort the raw results alphabetically (a behavior which can be restored if you like it -- [see below](#settings)).

## Table of Contents
- [Installation](#installation)
- [Command Line Options](#command-line-options)
- [Settings](#settings)
- [Examples](#examples)
- [Improvements and Fixes](#improvements-and-fixes)
- [Known Bugs](#known-bugs)

## Installation

### General observations

This script can be installed simply by downloading it and sourcing it from your `.zshrc`:

    source /path/to/zsh-z.plugin.zsh

For tab completion to work, you will want to have loaded `compinit`. The frameworks handle this themselves. If you are not using a framework, put

    autoload -U compinit && compinit

in your .zshrc somewhere below where you source `zsh-z.plugin.zsh`.

If you add

    zstyle ':completion:*' menu select

to your `.zshrc`, your completion menus will look very nice. This `zstyle` invocation should work with any of the frameworks below as well.

### For [antigen](https://github.com/zsh-users/antigen) users

Add the line

    antigen bundle agkozak/zsh-z

to your `.zshrc`, somewhere above the line that says `antigen apply`.

### For [oh-my-zsh](http://ohmyz.sh/) users

Execute the following command:

    git clone https://github.com/agkozak/zsh-z $ZSH_CUSTOM/plugins/zsh-z

and add `zsh-z` to the line of your `.zshrc` that specifies `plugins=()`, e.g. `plugins=( git zsh-z )`.

### For [zgen](https://github.com/tarjoilija/zgen) users

Add the line

    zgen load agkozak/zsh-z

somewhere above the line that says `zgen save`. Then run

    zgen reset
    zsh

to refresh your init script.

### For [zplug](https://github.com/zplug/zplug) users

Add the line

    zplug "agkozak/zsh-z"

somewhere above the line that says `zplug load`. Then run

    zplug install
    zplug load

to install `zsh-z`.

### For [zplugin](https://github.com/zdharma/zplugin) users

Add the line

    zplugin load agkozak/zsh-z

to your `.zshrc`.

## Command Line Options

- `-c`    Only match subdirectories of the current directory
- `-e`    Echo the best match without going to it
- `-h`    Display help
- `-l`    List all matches without going to them
- `-r`    Match by rank (i.e. how much time you spend in directories)
- `-t`    Time -- match by how recently you have been to directories
- `-x`    Remove the current directory from the database

# Settings

ZSH-z has environment variables (they all begin with `ZSHZ_`) that change its behavior if you set them; you can also keep your old ones if you have been using `rupa/z` (they begin with `_Z_`).

* `ZSHZ_CMD` changes the command name (default: `z`)
* `ZSHZ_COMPLETION` can be `'frecent'` (default) or `'legacy'`, depending on whether you want your completion results sorted according to frecency or simply sorted alphabetically
* `ZSHZ_DATA` changes the database file (default: `~/.z`)
* `ZSHZ_EXCLUDE_DIRS` is an array of directories to keep out of the database (default: empty)
* `ZSHZ_NO_RESOLVE_SYMLINKS` prevents symlink resolution (default: `0`)
* `ZSHZ_OWNER` allows usage when in `sudo -s` mode (default: empty)

## Improvements and Fixes

* `z -x` works, with the help of `chpwd_functions`.
* ZSH-z works on Solaris.
* ZSH-z uses the "new" `zshcompsys` completion system instead of the old `compctl` one.
* There is no error message when the database file has not yet been created.
* There is support for special characters (e.g. '[') in directory names.
* If `z -l` only returns one match, a common root is not printed.
* Exit status codes increasingly make sense.
* Completions work with options `-c`, `-r`, and `-t`.


## Known Bugs
* It is possible to run a completion on a string with spaces in it, e.g. `z us bi<TAB>` might take you to `/usr/local/bin`. This works, but as things stand, after the completion the command line reads `z us /usr/local/bin`. I am working on eliminating this glitch.
* The database file can occasionally be lost in a race condition. I am having increasing success mitigating this behavior.
