# ZLE completion widget transformation logic.
#
# `_zshz_zle_completion_widget` rewrites `z us lo bi` into `z us*lo*bi` before
# delegating to the original Tab binding (zsh-z.plugin.zsh:996-1031). We
# can't drive a real ZLE session non-interactively, so we stub `zle` to a
# no-op function and inspect LBUFFER after the call.

test_widget_joins_multiple_search_terms_with_asterisk() {
  local out
  out=$(zshz_in_fresh_shell "
    zle() { return 0 }
    LBUFFER='z us lo bi'
    _zshz_zle_completion_widget
    print -- \$LBUFFER
  ")
  assert_eq "z us*lo*bi" "$out" "multiple terms should be joined with *"
}

test_widget_preserves_flags_before_search_terms() {
  local out
  out=$(zshz_in_fresh_shell "
    zle() { return 0 }
    LBUFFER='z -e foo bar'
    _zshz_zle_completion_widget
    print -- \$LBUFFER
  ")
  assert_eq "z -e foo*bar" "$out" "flags should remain separate from joined search terms"
}

test_widget_passes_through_single_term() {
  local out
  out=$(zshz_in_fresh_shell "
    zle() { return 0 }
    LBUFFER='z foo'
    _zshz_zle_completion_widget
    print -- \$LBUFFER
  ")
  assert_eq "z foo" "$out" "single term should not be transformed"
}

test_widget_does_not_retrigger_on_completed_absolute_path() {
  # When LBUFFER ends with a space after an absolute path (the result of a
  # successful prior completion), the widget should bail so a second Tab
  # doesn't re-trigger and produce a duplicate.
  local out
  out=$(zshz_in_fresh_shell "
    zle() { return 0 }
    LBUFFER='z /usr/local/bin '
    _zshz_zle_completion_widget
    print -- \$LBUFFER
  ")
  assert_eq "z /usr/local/bin " "$out" "completed absolute path should pass through unchanged"
}

test_widget_recognizes_long_flags() {
  local out
  out=$(zshz_in_fresh_shell "
    zle() { return 0 }
    LBUFFER='z --add foo bar'
    _zshz_zle_completion_widget
    print -- \$LBUFFER
  ")
  assert_eq "z --add foo*bar" "$out" "long flags should be classified as flags, not joined into search terms"
}

test_widget_uses_custom_ZSHZ_CMD() {
  local out
  out=$(zsh --no-rcs -c "
    bindkey -M main '^I' expand-or-complete
    ZSHZ_CMD=zoo
    source '$PLUGIN_DIR/zsh-z.plugin.zsh'
    zle() { return 0 }
    LBUFFER='zoo us lo'
    _zshz_zle_completion_widget
    print -- \$LBUFFER
  ")
  assert_eq "zoo us*lo" "$out" "widget should respect a custom ZSHZ_CMD"
}
