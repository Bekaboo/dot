# Initialize fish shell once on login, including settings global variables etc.
if not status is-login
    exit
end

# Automatically login to proot-distro on termux
if type -q proot-distro
    and test -n "$PROOT_DISTRO"
    and test -n "$PROOT_USER"
    exec proot-distro login $PROOT_DISTRO --user $PROOT_USER --termux-home
end

# Setup paths
# macOS homebrew
fish_add_path /opt/homebrew/bin /usr/local/bin
if type -q brew
    eval (brew shellenv)
end

# Other install paths
# Homebrew `brew shellenv` uses `--move` to prepend its paths, overriding our
# custom wrappers in `~/.bin` (e.g., `~/.bin/fzf`). We use `--move` again here
# to ensure these paths take priority over homebrew's
fish_add_path --move \
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

if test "$TERM" = linux
    echo -en "\e]P00D0C0C" #black
    echo -en "\e]P1C4746E" #darkred
    echo -en "\e]P28A9A7B" #darkgreen
    echo -en "\e]P3D2B788" #brown
    echo -en "\e]P48BA4B0" #darkblue
    echo -en "\e]P5A292A3" #darkmagenta
    echo -en "\e]P68EA4A2" #darkcyan
    echo -en "\e]P7B4B3A7" #lightgrey
    echo -en "\e]P87F827F" #darkgrey
    echo -en "\e]P9E46876" #red
    echo -en "\e]PA87A987" #green
    echo -en "\e]PBDCA561" #yellow
    echo -en "\e]PC7FB4CA" #blue
    echo -en "\e]PD938AA9" #magenta
    echo -en "\e]PE7AA89F" #cyan
    echo -en "\e]PFB4B8B4" #white
    clear #for background artifacting
end

# Ensure color theme files are correctly linked
type -q setbg; and setbg &
type -q setcolors; and setcolors &
