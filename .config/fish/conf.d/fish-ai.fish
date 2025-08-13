if not status is-login
    exit
end

set -Ux FISH_AI_KEYMAP_1 ctrl-_ # convert comment to command or explain
set -Ux FISH_AI_KEYMAP_2 alt-/ # autocomplete or fix previous command
