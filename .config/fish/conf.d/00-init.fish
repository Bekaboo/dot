# Initialize fish shell, including settings global variables etc.
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

if type -q tmux
    and test -n "$SSH_TTY"
    and test -z "$SCREEN"
    and test -z "$TMUX"
    and test -z "$VIM"
    and test -z "$NVIM"
    and test -z "$INSIDE_EMACS"
    and test "$TERM_PROGRAM" != vscode
    and test "$TERM" != linux
    if tmux ls 2>/dev/null | string match -rvq attached
        and test "$PWD" = "$HOME"
        exec tmux at
    else
        exec tmux
    end
end
