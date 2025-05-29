if not status is-interactive
    exit
end

# Source:
# https://stackoverflow.com/questions/65722822/fish-shell-add-newline-before-prompt-only-when-previous-output-exists
function __postexec_append_newline --on-event fish_postexec \
    --description 'Add newline before prompt only when previous output exists' \
    --argument-names cmd
    # Don't add extra newline if the commandline is 'clear',
    # The commandline is passed as the first parameter,
    # see https://fishshell.com/docs/current/language.html#event
    if string match -aqr $cmd '^\\s*clear\\s*$'
        return
    end
    echo
end
