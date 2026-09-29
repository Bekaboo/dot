if not status is-interactive
    exit
end

# Disable venv prompt provided by `activate.fish` -- we handle it ourselves in
# `functions/fish_right_prompt.fish`
# Also, shouldn't export this variable with `set -gx` as we don't want to to
# affect other shells, e.g. `bash` that is nested in `fish`
set -g VIRTUAL_ENV_DISABLE_PROMPT true

# Restore old behavior of alt-backspace (delete a word instead of token), see:
# https://github.com/fish-shell/fish-shell/issues/10926
# https://github.com/fish-shell/fish-shell/pull/10766
bind alt-backspace backward-kill-word
