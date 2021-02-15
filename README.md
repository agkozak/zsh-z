# ZSH-z

[![MIT License](img/mit_license.svg)](https://opensource.org/licenses/MIT)
![ZSH version 4.3.11 and higher](img/zsh_4.3.11_plus.svg)
[![GitHub stars](https://img.shields.io/github/stars/agkozak/zsh-z.svg)](https://github.com/agkozak/zsh-z/stargazers)

![ZSH-z demo](img/demo.gif)

ZSH-z is a command line tool that allows you to jump quickly to directories that you have visited frequently in the past, or recently -- but most often a combination of the two (a concept known as ["frecency"](https://en.wikipedia.org/wiki/Frecency)). It works by keeping track of when you go to directories and how much time you spend in them. It is then in the position to guess where you want to go when you type a partial string, e.g. `z src` might take you to `~/src/zsh`. `z zsh` might also get you there, and `z c/z` might prove to be even more specific -- it all depends on your habits and how much time you have been using ZSH-z to build up a database. After using ZSH-z for a little while, you will get to where you want to be by typing considerably less than you would need if you were using `cd`.

ZSH-z is a native ZSH port of [rupa/z](https://github.com/rupa/z), a tool written for `bash` and ZSH that uses embedded `awk` scripts to do the heavy lifting. It was quite possibly my most used command line tool for a couple of years. I decided to translate it, `awk` parts and all, into pure ZSH script, to see if by eliminating calls to external tools (`awk`, `sort`, `date`, `sed`, `mv`, `rm`, and `chown`) and reducing forking through subshells I could make it faster. The performance increase is impressive, particularly on systems where forking is slow, such as Cygwin, MSYS2, and WSL. I have found that, in those environments, switching directories using ZSH-z can be over 100% faster than it is using `rupa/z`.

There is a noteworthy stability increase as well. Race conditions have always been a problem with `rupa/z`, and users of that utility will occasionally lose their `.z` databases. By having ZSH-z only use ZSH (`rupa/z` uses a hybrid shell code that works on `bash` as well), I have been able to implement a `zsh/system`-based file-locking mechanism similar to [the one @mafredri once proposed for `rupa/z`](https://github.com/rupa/z/pull/199). It is now nearly impossible to crash the database, even through extreme testing.

There are other, smaller improvements which I try to document in [Improvements and Fixes](#improvements-and-fixes). These include the new default behavior of sorting your tab completions by frecency rather than just letting ZSH sort the raw results alphabetically (a behavior which can be restored if you like it -- [see below](#settings)).

ZSH-z is a drop-in replacement for `rupa/z` and will, by default, use the same database (`~/.z`), so you can go on using `rupa/z` when you launch `bash`.

## Table of Contents
- [News](#news)
- [Installation](#installation)
- [Command Line Options](#command-line-options)
- [Settings](#settings)
- [Case Sensitivity](#case-sensitivity)
- [`ZSHZ_UNCOMMON`](#zshz_uncommon)
- [Improvements and Fixes](#improvements-and-fixes)
- [Migrating from Other Tools](#migrating-from-other-tools)
- [`COMPLETE_ALIASES`](#complete_aliases)
- [Known Bugs](#known-bugs)

## News

<details>
    <summary>Here are the latest features and updates.</summary>

- February 15, 2021
  + Ranks are displayed the way `rupa/z` now displays them, i.e. as large integers. This should help ZSH-z to integrate with other tools.
- January 31, 2021
  + ZSH-z is now efficient enough that, on MSYS2 and Cygwin, it is faster to run it in the foreground than it is to fork a subshell for it.
  + `_zshz_precmd` simply returns if `PWD` is `HOME` or in `ZSH_EXCLUDE_DIRS`, rather than waiting for `zshz` to do that.
- January 17, 2021
  + Made sure that the `PUSHD_IGNORE_DUPS` option is respected.
- January 14, 2021
  + The `z -h` help text now breaks at spaces.
  + `z -l` was not working for ZSH version < 5.
- January 11, 2021
  + Major refactoring of the code.
  + `z -lr` and `z -lt` work as expected.
  + `EXTENDED_GLOB` has been disabled within the plugin to accomodate old-fashioned Windows directories with names such as `Progra~1`.
  + Removed `zshelldoc` documentation.
- January 6, 2021
  + I have corrected the frecency routine so that it matches `rupa/z`'s math, but for the present, ZSH-z will continue to display ranks as 1/10000th of what they are in `rupa/z` -- [they had to multiply theirs by 10000](https://github.com/rupa/z/commit/f1f113d9bae9effaef6b1e15853b5eeb445e0712) to work around `bash`'s inadequacies at dealing with decimal fractions.
- January 5, 2021
  + If you try `z foo`, and `foo` is not in the database but `${PWD}/foo` is a valid directory, ZSH-z will `cd` to it.
- December 22, 2020
  + `ZSHZ_CASE`: when set to `ignore`, pattern matching is case-insensitive; when set to `smart`, patterns are matched case-insensitively when they are all lowercase and case-sensitively when they have uppercase characters in them (a behavior very much like Vim's `smartcase` setting).
  + `ZSHZ_KEEP_DIRS` is an array of directory names that should not be removed from the database, even if they are not currently available (useful when a drive is not always mounted).
  + Symlinked datafiles were having their symlinks overwritten; this bug has been fixed.

</details>

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

### For [prezto](https://github.com/sorin-ionescu/prezto) users

Execute the following command:

    git clone https://github.com/agkozak/zsh-z.git ~/.zprezto-contrib/zsh-z

Then edit your `~/.zpreztorc` file. Make sure the line that says

    zstyle ':prezto:load' pmodule-dirs $HOME/.zprezto-contrib

is uncommented. Then find the section that specifies which modules are to be loaded; it should look something like this:

    zstyle ':prezto:load' pmodule \
        'environment' \
        'terminal' \
        'editor' \
        'history' \
        'directory' \
        'spectrum' \
        'utility' \
        'completion' \
        'prompt'

Add a backslash to the end of the last line add `'zsh-z'` to the list, e.g.

    zstyle ':prezto:load' pmodule \
        'environment' \
        'terminal' \
        'editor' \
        'history' \
        'directory' \
        'spectrum' \
        'utility' \
        'completion' \
        'prompt' \
        'zsh-z'

Then relaunch `zsh`.

### For [zgen](https://github.com/tarjoilija/zgen) users

Add the line

    zgen load agkozak/zsh-z

somewhere above the line that says `zgen save`. Then run

    zgen reset
    zsh

to refresh your init script.

### For [Zim](https://github.com/zimfw/zimfw)

Add the following line to your `.zimrc`:

    zmodule https://github.com/agkozak/zsh-z

Then run

    zimfw install

and restart your shell.

### For [Zinit](https://github.com/zdharma/zinit) (formerly `zplugin`) users

Add the line

    zinit load agkozak/zsh-z

to your `.zshrc`.

`zsh-z` supports `zinit`'s `unload` feature; just run `zinit unload agkozak/zshz` to restore the shell to its state before `zsh-z` was loaded.

### For [zplug](https://github.com/zplug/zplug) users

Add the line

    zplug "agkozak/zsh-z"

somewhere above the line that says `zplug load`. Then run

    zplug install
    zplug load

to install `zsh-z`.

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
* `ZSHZ_KEEP_DIRS` is an array of directories that should not be removed from the database, even if they are not currently available (useful when a drive is not always mounted) (default: empty)
* `ZSHZ_MAX_SCORE` is the maximum combined score the database entries can have before they begin to age and potentially drop out of the database (default: 9000)
* `ZSHZ_NO_RESOLVE_SYMLINKS` prevents symlink resolution (default: `0`)
* `ZSHZ_OWNER` allows usage when in `sudo -s` mode (default: empty)

## Case sensitivity

The default behavior of ZSH-z is to try to find a case-sensitive match. If there is none, then ZSH-z tries to find a case-insensitive match.

Some users prefer simple case-insensitivity; this behavior can be enabled by setting

    ZSHZ_CASE=ignore

If you like Vim's `smartcase` setting, where lowercase patterns are case-insensitive while patterns with any uppercase characters are treated case-sensitively, try setting

    ZSHZ_CASE=smart

## `ZSHZ_UNCOMMON`

A common complaint about the default behavior of `rupa/z` and ZSH-z involves "common prefixes." If you type `z code` and the best matches, in increasing order, are

    /home/me/code/foo
    /home/me/code/bar
    /home/me/code/bat

ZSH-z will see that all possible matches share a common prefix and will send you to that directory -- `/home/me/code` -- which is often a desirable result. But if the possible matches are

    /home/me/.vscode/foo
    /home/me/code/foo
    /home/me/code/bar
    /home/me/code/bat

then there is no common prefix. In this case, `z code` will simply send you to the highest-ranking match, `/home/me/code/bat`.

You may enable an alternate, experimental behavior by setting `ZSHZ_UNCOMMON=1`. If you do that, ZSH-z will not jump to a common prefix, even if one exists. Instead, it chooses the highest-ranking match -- but it drops any subdirectories that do not include the search term. So if you type `z bat` and `/home/me/code/bat` is the best match, that is exactly where you will end up. If, however, you had typed `z code` and the best match was also `/home/me/code/bat`, you would have ended up in `/home/me/code` (because `code` was what you had searched for). This feature is still in development, and feedback is welcome.

## Improvements and Fixes

* `z -x` works, with the help of `chpwd_functions`.
* ZSH-z works on Solaris.
* ZSH-z uses the "new" `zshcompsys` completion system instead of the old `compctl` one.
* There is no error message when the database file has not yet been created.
* There is support for special characters (e.g. `[`) in directory names.
* If `z -l` only returns one match, a common root is not printed.
* Exit status codes increasingly make sense.
* Completions work with options `-c`, `-r`, and `-t`.
* If `~/foo` and `~/foob` are matches, `~/foo` is *not* the common root. Only a common parent directory can be a common root.

## Migrating from Other Tools

ZSH-z's database format is identical to that of `rupa/z`. You may switch freely between the two tools (I still use `rupa/z` for `bash`). `fasd` also uses that database format, but it stores it by default in `~/.fasd`, so you will have to `cp ~/.fasd ~/.z` if you want to use your old directory history.

If you are coming to ZSH-z (or even to the original `rupa/z`, for that matter) from `autojump`, try using my [`jumpstart-z`](https://github.com/agkozak/jumpstart-z/blob/master/jumpstart-z) tool to convert your old database to the ZSH-z format.

## `COMPLETE_ALIASES`

`z`, or any alternative you set up using `$ZSH_CMD` or `$_Z_CMD`, is an alias. `setopt COMPLETE_ALIASES` divorces the tab completion for aliases from the underlying commands they invoke, so if you enable `COMPLETE_ALIASES`, tab completion for ZSH-z will be broken. You can get it working again, however, by adding under

    setopt COMPLETE_ALIASES

the line

    compdef _zshz ${ZSHZ_CMD:-${_Z_CMD:-z}}

That will re-bind `z` or the command of your choice to the underlying ZSH-z function.

## Known Bugs
It is possible to run a completion on a string with spaces in it, e.g. `z us bi<TAB>` might take you to `/usr/local/bin`. This works, but as things stand, after the completion the command line reads

    z us /usr/local/bin.

You get where you want to go, but the detritus on the command line is annoying. This is also a problem in `rupa/z`, but I am keen on eventually eliminating this glitch. Advice is welcome.
