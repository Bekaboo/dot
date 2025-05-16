# Initialize fish shell, including settings global variables etc.

# Setup for macOS homebrew
if test (uname) = Darwin
    fish_add_path -p /opt/homebrew/bin /usr/local/bin

    if type -q brew
        eval (brew shellenv)
    end
end

# Other install paths
fish_add_path -p \
    $HOME/.bin \
    $HOME/.local/bin \
    $HOME/.cargo/bin \
    $HOME/go/bin

if test -f $HOME/.envvars
    source $HOME/.envvars
end

if test -f $__fish_config_dir/fish_envvars
    source $__fish_config_dir/fish_envvars
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

if type -q proot-distro
    and test -n "$TERMUX_VERSION"
    and test -n "$PROOT_DISTRO"
    and test -n "$PROOT_USER"
    exec proot-distro login $PROOT_DISTRO --user $PROOT_USER --termux-home
end
