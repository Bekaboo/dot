# Source:
# https://stackoverflow.com/questions/65722822/fish-shell-add-newline-before-prompt-only-when-previous-output-exists
function postexec_test --on-event fish_postexec \
    --description 'Add newline before prompt only when previous output exists'
   echo
end
