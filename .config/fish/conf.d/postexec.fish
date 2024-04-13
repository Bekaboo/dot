# Source:
# https://stackoverflow.com/questions/65722822/fish-shell-add-newline-before-prompt-only-when-previous-output-exists
function postexec_apppend_newline --on-event fish_postexec \
    --description 'Add newline before prompt only when previous output exists'
    # Don't add extra newline if the commandline is 'clear',
    # The commandline is passed as the first parameter,
    # see https://fishshell.com/docs/current/language.html#event
    if string match -aqr $argv[1] '^\\s*clear\\s*\$'
        return
    end
    echo
end
