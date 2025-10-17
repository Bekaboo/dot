if not status is-login
    exit
end

# Set rg config path
set -Ux RIPGREP_CONFIG_PATH $HOME/.ripgreprc
