if not status is-login
    exit
end

set -Ux FISH_AI_KEYMAP_1 ctrl-_ # convert comment to command or explain
set -Ux FISH_AI_KEYMAP_2 alt-/ # autocomplete or fix previous command

# Switch fish-ai config based on FISH_AI_CONFIG envvar
if test -n "$FISH_AI_CONFIG"
    ln -s $HOME/.config/fish-ai.$FISH_AI_CONFIG.ini $HOME/.config/fish-ai.ini
end
