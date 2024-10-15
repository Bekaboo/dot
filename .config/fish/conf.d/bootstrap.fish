# Automatically fetch fisher plugin manager if not installed

# Only automatically install fisher in interactive shell to avoid infinite loop
# when fisher is not installed (fisher install script uses non-interactive
# fisher to install)
if not status is-interactive
    return
end

if type -q fisher
    return
end

set -l state_home (test -n "$XDG_STATE_HOME";
                    and echo "$XDG_STATE_HOME";
                    or echo "$HOME/.local/state")
set -l fish_state_dir "$state_home/fish"

# Previously asked to not install fisher
if test -f "$fish_state_dir/no-bootstrap"
    return
end

# Ask if to install fisher
set -l choice (read -P 'Install fisher plugin manager? [y]es/[n]o/[never] ' -l)
switch $choice
    case Y y YES Yes yes
        curl -sL 'https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish' \
            | source && fisher install jorgebucaran/fisher
        fisher update
    case NEVER Never never
        if not test -d "$fish_state_dir"
            mkdir -p "$fish_state_dir"
        end
        touch "$fish_state_dir/no-bootstrap"
        echo "Fisher bootstrap disabled"
        echo "Remove '$fish_state_dir/no-bootstrap' to re-enable bootstrap"
end
