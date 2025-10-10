if not status is-interactive
    exit
end

# Source:
# https://stackoverflow.com/questions/65722822/fish-shell-add-newline-before-prompt-only-when-previous-output-exists
function __postexec_append_newline --on-event fish_postexec \
    --description 'Add newline before prompt only when previous output exists' \
    --argument-names cmd
    echo
end
