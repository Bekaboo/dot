# Initialize fish shell, including settings global variables etc.

# Setup for macOS homebrew
if type -q brew
    fish_add_path -p (brew --prefix)/bin
    eval (brew shellenv)
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

for editor in nvim vim vi
    if type -q $editor
        set -gx EDITOR $editor
        if test $editor = nvim
            set -gx MANPAGER 'nvim +Man!'
        end
        break
    end
end

# Set rg config path
set -gx RIPGREP_CONFIG_PATH $HOME/.ripgreprc

if status is-login
    and type -q proot-distro
    and test -n "$TERMUX_VERSION"
    and test -n "$PROOT_DISTRO"
    and test -n "$PROOT_USER"
    exec proot-distro login $PROOT_DISTRO --user $PROOT_USER --termux-home
end
