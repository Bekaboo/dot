# Plugin settings
# Don't bootstrap in non-interactive shells
if not status is-interactive
    exit
end

# Automatically fetch fisher plugin manager, setup paths and sync plugins
function __bootstrap
    # Add custom `$fisher_path` to fish paths
    set -l data_home (test -n "$XDG_DATA_HOME";
                  and echo "$XDG_DATA_HOME";
                  or echo "$HOME/.local/share")
    set -gx fisher_path "$data_home/fish/plugin"

    # Set fish state directory
    set -l state_home (test -n "$XDG_STATE_HOME";
                    and echo "$XDG_STATE_HOME";
                    or echo "$HOME/.local/state")
    set -l fish_state_dir "$state_home/fish"

    # Don't use `set -gx` here as lists as environment variables
    # (variable set with `-x`) will collapse to strings when exported to subshell
    if not contains "$fisher_path/functions" $fish_function_path
        set -g fish_function_path $fish_function_path[1] \
            "$fisher_path/functions" $fish_function_path[2..-1]
    end

    if not contains "$fisher_path/completions" $fish_complete_path
        set -g fish_complete_path $fish_complete_path[1] \
            "$fisher_path/completions" $fish_complete_path[2..-1]
    end

    for file in $fisher_path/conf.d/*.fish
        source $file
    end

    # Return if fisher already installed
    if type -q fisher
        return
    end
    for path in $fish_function_path
        if test -f "$path/fisher.fish"
            return
        end
    end

    # User has declared not to bootstrap plugins on startup
    if test -f "$fish_state_dir/no-bootstrap"
        return 1
    end

    set -l choice (string trim (read -P \
        'Install fisher plugin manager? [y]es/[n]o/[never] ' -l))
    switch $choice
        case Y y YES Yes yes
            curl -sL 'https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish' | source
            set -l plugins_file "$__fish_config_dir/fish_plugins"
            if test -s "$plugins_file"
                cat "$plugins_file" | fisher install
            else
                fisher install jorgebucaran/fisher
            end
            # Reload shell after update for plugins to take effect
            exec fish -l
        case NEVER Never never
            if not test -d "$fish_state_dir"
                mkdir -p "$fish_state_dir"
            end
            touch "$fish_state_dir/no-bootstrap"
            echo "Fisher bootstrap disabled"
            echo "Remove '$fish_state_dir/no-bootstrap' to re-enable bootstrap"
    end

    return 1
end

if not __bootstrap
    exit
end
