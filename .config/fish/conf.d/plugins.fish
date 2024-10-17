# Automatically fetch fisher plugin manager if not installed

# Custom `$fisher_path` settings
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

# Patch plugins after installing or upgrading plugins
# Patch fzf
function __patch_fzf --on-event fzf_install --on-event fzf_update
    set -l patch_dir "$__fish_config_dir/patches"
    set -l patch_file "$patch_dir/fzf.patch"
    if not test -d "$patch_dir"; or not test -f "$patch_file"
        return
    end

    patch -Rsfd "$fisher_path" -p1 -i "$patch_file" &>/dev/null
    patch -fd "$fisher_path" -p1 -i "$patch_file"
end

# Early return if we already have fisher installed
for path in $fish_function_path
    if test -f "$path/fisher.fish"
        return
    end
end

# Else try bootstrap fisher & plugins
set -l state_home (test -n "$XDG_STATE_HOME";
                    and echo "$XDG_STATE_HOME";
                    or echo "$HOME/.local/state")
set -l fish_state_dir "$state_home/fish"

# Previously asked to not install fisher, abort
if test -f "$fish_state_dir/no-bootstrap"
    return
end

# Ask if to install fisher if in interactive shell
if status is-interactive
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
end
