# Initialize fish shell, including settings global variables etc.
fish_add_path -p \
    $HOME/.bin \
    $HOME/.local/bin \
    $HOME/.cargo/bin \
    $HOME/go/bin

if test -f $__fish_config_dir/fish_exports
    source $__fish_config_dir/fish_exports
end

if type -q nvim
    set -gx EDITOR nvim
    set -gx MANPAGER 'nvim +Man!'
else if type -q vim
    set -gx EDITOR vim
else if type -q vi
    set -gx EDITOR vi
end

if type -q xhost
    xhost +local:root &>/dev/null
end

# Set rg config path
set -gx RIPGREP_CONFIG_PATH $HOME/.ripgreprc
