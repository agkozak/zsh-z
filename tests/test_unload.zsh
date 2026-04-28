# Plugin unload / reload contract.
#
# Per the Zsh Plugin Standard
# (https://github.com/agkozak/Zsh-100-Commits-Club/blob/master/Zsh-Plugin-Standard.adoc#unload-fun),
# `zsh-z_plugin_unload` should fully remove the plugin: drop its functions and
# widget, restore the prior Tab binding, remove its precmd/chpwd hooks, and
# unset the ZSHZ global. Re-sourcing afterward should bring everything back.
#
# Each test runs in a fresh `zsh --no-rcs -c` subshell.

test_unload_removes_zshz_function() {
  local out
  out=$(zshz_in_fresh_shell '
    zsh-z_plugin_unload
    print -- ${+functions[zshz]}
  ')
  assert_eq "0" "$out" "zshz function should be gone after unload"
}

test_unload_unsets_ZSHZ_global() {
  local out
  out=$(zshz_in_fresh_shell '
    zsh-z_plugin_unload
    print -- ${+ZSHZ}
  ')
  assert_eq "0" "$out" "ZSHZ should be unset after unload"
}

test_unload_removes_widget() {
  local out
  out=$(zshz_in_fresh_shell '
    zsh-z_plugin_unload
    print -- ${+widgets[_zshz_zle_completion_widget]}
  ')
  assert_eq "0" "$out" "widget should be deleted after unload"
}

test_unload_restores_prior_tab_binding() {
  local out
  out=$(zshz_in_fresh_shell "
    zsh-z_plugin_unload
    bindkey -M main '^I'
  ")
  assert_contains "expand-or-complete" "$out" "Tab should return to its prior binding"
  assert_not_contains "_zshz_zle_completion_widget" "$out" "widget should not still be on Tab"
}

test_unload_leaves_user_rebound_tab_alone() {
  # If the user rebinds Tab themselves after sourcing, unload must NOT silently
  # undo that rebind. Regression for commit e55ae41 ("unload: only restore Tab
  # binding when appropriate").
  local out
  out=$(zshz_in_fresh_shell "
    bindkey -M main '^I' menu-complete
    zsh-z_plugin_unload
    bindkey -M main '^I'
  ")
  assert_contains "menu-complete" "$out" "user's later rebind should survive unload"
}

test_unload_removes_hooks() {
  local out
  out=$(zshz_in_fresh_shell '
    zsh-z_plugin_unload
    print precmd=${precmd_functions[(r)_zshz_precmd]:-none}
    print chpwd=${chpwd_functions[(r)_zshz_chpwd]:-none}
  ')
  assert_contains "precmd=none" "$out" "_zshz_precmd hook should be gone"
  assert_contains "chpwd=none" "$out" "_zshz_chpwd hook should be gone"
}

test_unload_then_reload_restores_function_and_widget() {
  local out
  local -a lines
  out=$(zshz_in_fresh_shell "
    zsh-z_plugin_unload
    source '$PLUGIN_DIR/zsh-z.plugin.zsh'
    print -- \${+functions[zshz]}
    print -- \${+widgets[_zshz_zle_completion_widget]}
    bindkey -M main '^I'
  ")
  lines=( ${(f)out} )
  assert_eq "1" "$lines[1]" "zshz function should exist after reload"
  assert_eq "1" "$lines[2]" "widget should exist after reload"
  assert_contains "_zshz_zle_completion_widget" "$lines[3]" "Tab should be bound to widget after reload"
}

test_reload_after_unload_captures_current_tab_binding() {
  # After unload restored the prior binding, re-sourcing should treat the
  # *current* Tab binding as "the binding to chain to" -- not stale state from
  # before the unload.
  local out
  out=$(zshz_in_fresh_shell "
    zsh-z_plugin_unload
    bindkey -M main '^I' menu-complete
    source '$PLUGIN_DIR/zsh-z.plugin.zsh'
    print -- \$ZSHZ[TAB_BINDING]
  ")
  assert_eq "menu-complete" "$out" "reload should capture the binding present at reload time"
}
# vim: fdm=indent:ts=2:et:sts=2:sw=2:
