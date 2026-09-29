if not status is-interactive
    exit
end

# Keybindings provided by fzf
if type -q fzf_key_bindings
    fzf_key_bindings
end

# Keybindings provided by fzf.fish plugin
# Change default to avoid conflict with tmux bindings
if type -q fzf_configure_bindings
    fzf_configure_bindings \
        --directory=\ct \
        --processes=\cq \
        --git_log=\cx\cl \
        --git_status=\cx\cs
end
