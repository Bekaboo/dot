# Disable venv prompt provided by `activate.fish` -- we handle it ourselves in
# `functions/fish_right_prompt.fish`
# Also, shouldn't export this variable with `set -gx` as we don't want to to
# affect other shells, e.g. `bash` that is nested in `fish`
if status is-interactive
    set -g VIRTUAL_ENV_DISABLE_PROMPT true
end
