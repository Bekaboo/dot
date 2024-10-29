# Plugin settings

# Automatically fetch fisher plugin manager, setup paths and sync plugins
function __bootstrap
    # Add custom `$fisher_path` to fish paths
    set -l data_home (test -n "$XDG_DATA_HOME";
                  and echo "$XDG_DATA_HOME";
                  or echo "$HOME/.local/share")
    set -gx fisher_path "$data_home/fish/plugin"

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
    for path in $fish_function_path
        if test -f "$path/fisher.fish"
            return
        end
    end

    # Don't bootstrap in non-interactive shells
    if not status is-interactive
        return 1
    end

    set -l choice (read -P 'Install fisher plugin manager? [y]es/[n]o/[never] ' -l)
    switch $choice
        case Y y YES Yes yes
            curl -sL 'https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish' | source
            set -l plugins_file "$__fish_config_dir/fish_plugins"
            if test -f "$plugins_file"
                cat "$plugins_file" | fisher install
            else
                fisher install jorgebucaran/fisher
            end

            # reload shell after update for e.g. patches to take effect
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

# Patch plugins after installing or upgrading plugins
function __setup_patch_hook
    set -l plugin_name $argv[1]
    eval "function __patch_$plugin_name --on-event "$plugin_name"_install --on-event "$plugin_name"_update
            set -l patch_dir \$__fish_config_dir/patches
            set -l patch_file \$patch_dir/$plugin_name.patch
            if not test -d \$patch_dir; or not test -f \$patch_file
                return
            end
            patch -Rsfd \$fisher_path -p1 -i \$patch_file &>/dev/null
            patch -fd \$fisher_path -p1 -i \$patch_file
        end"
end

for patch in $__fish_config_dir/patches/*.patch
    __setup_patch_hook (basename $patch .patch)
end

if not __bootstrap
    exit
end

# Plugin configs
# Fzf configs
# Use custom previewer script if available
if type -q fzf-file-previewer
    set -gx fzf_preview_dir_cmd fzf-file-previewer
    set -gx fzf_preview_file_cmd fzf-file-previewer
end

# Include hidden files
set fzf_fd_opts -p -H -L -td -tf -tl --mount -c=always

# Fzf keybindings
if type -q fzf_configure_bindings
    fzf_configure_bindings --git_status=\e\cg --git_stash=\e\cs
end
