# ~/.bashrc
# vim: ft=sh ts=4 sw=4 sts=4 et :

__has() {
    command -v "$1" >/dev/null 2>&1
}

pathadd() {
    if [[ ":$PATH:" != *":$1:"* ]]; then
        PATH="$1${PATH:+":$PATH"}"
    fi
}

pathadd "${HOME}/.bin"
pathadd "${HOME}/.local/bin"
pathadd "${HOME}/.cargo/bin"
pathadd "${HOME}/go/bin"
export PATH

[[ -r "${HOME}/.envvars" ]] && source "${HOME}/.envvars"
[[ -r "${HOME}/.bash_envvars" ]] && source "${HOME}/.bash_envvars"

if __has nvim; then
    export EDITOR=nvim
    export MANPAGER=nvim\ +'Man!'
elif __has vim; then
    export EDITOR=vim
elif __has vi; then
    export EDITOR=vi
fi

if __has xhost; then
    xhost +local:root >/dev/null 2>&1
fi

# Set rg config path
export RIPGREP_CONFIG_PATH=${HOME}/.ripgreprc

if __has proot-distro &&
    [[ -n "$TERMUX_VERSION" ]] &&
    [[ -n "$PROOT_DISTRO" ]] &&
    [[ -n "$PROOT_USER" ]]; then
    exec proot-distro login "$PROOT_DISTRO" --user "$PROOT_USER" --termux-home
fi

if __has tmux &&
    [[ -n "$SSH_TTY" ]] &&
    [[ -z "$SCREEN" ]] &&
    [[ -z "$TMUX" ]] &&
    [[ -z "$VIM" ]] &&
    [[ -z "$NVIM" ]] &&
    [[ -z "$INSIDE_EMACS" ]] &&
    [[ "$TERM_PROGRAM" != 'vscode' ]] &&
    [[ "$TERM" != 'linux' ]]; then
    if (tmux ls 2>/dev/null | grep -vq attached) && 
        [[ "$PWD" = "$HOME" ]]; then
        exec tmux at
    else
        exec tmux
    fi
fi

[[ $- != *i* ]] && return

if shopt -q login_shell && __has neofetch && [[ -z "$GREETED" ]]; then
    export GREETED=1
    clear -x
    neofetch
fi

# Enable colors for ls, etc. Prefer ~/.dir_colors
if type -P dircolors >/dev/null; then
    if [[ -f ~/.dir_colors ]]; then
        eval $(dircolors -b ~/.dir_colors)
    elif [[ -f /etc/DIR_COLORS ]]; then
        eval $(dircolors -b /etc/DIR_COLORS)
    fi
fi

# TTY Terminal Colors
if [[ "$TERM" == "linux" ]]; then
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
    clear                  #for background artifacting
fi

# 'less' highlights
export LESS_TERMCAP_mb=$'\e[1;32m'
export LESS_TERMCAP_md=$'\e[1;32m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[01;33m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;4;34m'

# fzf config variables
export FZF_DEFAULT_OPTS="--reverse \
    --preview='fzf-file-previewer {}' \
    --preview-window=right,55%,border-sharp,nocycle \
    --info=inline-right \
    --no-separator \
    --no-scrollbar \
    --border=none \
    --margin=1,0,0 \
    --height=~45% \
    --min-height=16 \
    --scroll-off=999 \
    --multi \
    --ansi \
    --color=fg:-1,bg:-1,hl:bold:cyan \
    --color=fg+:-1,bg+:-1,hl+:bold:cyan \
    --color=border:white,preview-border:white \
    --color=marker:bold:cyan,prompt:bold:red,pointer:bold:red \
    --color=gutter:-1,info:bold:red,spinner:cyan,header:white \
    --bind=ctrl-k:kill-line \
    --bind=alt-a:toggle-all \
    --bind=alt-{:first,alt-}:last \
    --bind=shift-up:preview-up,shift-down:preview-down \
    --bind=alt-v:preview-half-page-up,ctrl-v:preview-half-page-down"

if [[ -z "$DISPLAY" ]]; then
    export FZF_DEFAULT_OPTS=$(echo "$FZF_DEFAULT_OPTS" \
        '--no-unicode' \
        '--marker=+\ ' \
        '--pointer=>\ ')
fi

if __has fd; then
    export FZF_DEFAULT_COMMAND='fd -p -H -L -td -tf -tl --mount -c=always'
    export FZF_ALT_C_COMMAND='fd -p -H -L -td --mount -c=always'
elif __has fdfind; then
    export FZF_DEFAULT_COMMAND='fdfind -p -H -L -td -tf -tl --mount -c=always'
    export FZF_ALT_C_COMMAND='fdfind -p -H -L -td --mount -c=always'
else
    export FZF_DEFAULT_COMMAND="find -L . -mindepth 1 \\( \
            -path '*%*'                \
            -o -path '*.*Cache*/*'     \
            -o -path '*.*cache*/*'     \
            -o -path '*.*wine/*'       \
            -o -path '*.cargo/*'       \
            -o -path '*.conda/*'       \
            -o -path '*.dot/*'         \
            -o -path '*.env/*'         \
            -o -path '*.fonts/*'       \
            -o -path '*.git/*'         \
            -o -path '*.ipython/*'     \
            -o -path '*.java/*'        \
            -o -path '*.jupyter/*'     \
            -o -path '*.luarocks/*'    \
            -o -path '*.mozilla/*'     \
            -o -path '*.npm/*'         \
            -o -path '*.nvm/*'         \
            -o -path '*.steam*/*'      \
            -o -path '*.thunderbird/*' \
            -o -path '*.tmp/*'         \
            -o -path '*.venv/*'        \
            -o -path '*Cache*/*'       \
            -o -path '*\\\$*'          \
            -o -path '*\\~'            \
            -o -path '*__pycache__/*'  \
            -o -path '*cache*/*'       \
            -o -path '*dosdevices/*'   \
            -o -path '*env/*'          \
            -o -path '*node_modules/*' \
            -o -path '*vendor/*'       \
            -o -path '*venv/*'         \
            -o -fstype 'sysfs'         \
            -o -fstype 'devfs'         \
            -o -fstype 'devtmpfs'      \
            -o -fstype 'proc' \\) -prune \
        -o -type f -print \
        -o -type d -print \
        -o -type l -print 2> /dev/null | cut -b3-"
    export FZF_ALT_C_COMMAND="find -L . -mindepth 1 \\( \
            -path '*%*'                \
            -o -path '*.*Cache*/*'     \
            -o -path '*.*cache*/*'     \
            -o -path '*.*wine/*'       \
            -o -path '*.cargo/*'       \
            -o -path '*.conda/*'       \
            -o -path '*.dot/*'         \
            -o -path '*.fonts/*'       \
            -o -path '*.git/*'         \
            -o -path '*.ipython/*'     \
            -o -path '*.java/*'        \
            -o -path '*.jupyter/*'     \
            -o -path '*.luarocks/*'    \
            -o -path '*.mozilla/*'     \
            -o -path '*.npm/*'         \
            -o -path '*.nvm/*'         \
            -o -path '*.env/*'         \
            -o -path '*.steam*/*'      \
            -o -path '*.thunderbird/*' \
            -o -path '*.tmp/*'         \
            -o -path '*.venv/*'        \
            -o -path '*Cache*/*'       \
            -o -path '*\\\$*'          \
            -o -path '*\\~'            \
            -o -path '*__pycache__/*'  \
            -o -path '*cache*/*'       \
            -o -path '*dosdevices/*'   \
            -o -path '*env/*'          \
            -o -path '*node_modules/*' \
            -o -path '*vendor/*'       \
            -o -path '*venv/*'         \
            -o -fstype 'sysfs'         \
            -o -fstype 'devfs'         \
            -o -fstype 'devtmpfs'      \
            -o -fstype 'proc' \\) -prune \
        -o -type d -print 2> /dev/null | cut -b3-"
fi
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_CTRL_R_OPTS='--no-preview'
export FZF_PREVIEW_DISABLE_UB='true' # Disable ueberzug preview

[[ -r /usr/share/fzf/key-bindings.bash ]] && . /usr/share/fzf/key-bindings.bash
[[ -r /usr/share/fzf/completion.bash ]] && . /usr/share/fzf/completion.bash

# Ensure color theme files are correctly linked
if __has checkbg; then
    checkbg &
elif __has setbg; then
    setbg &
fi
__has setcolors && setcolors &

# Change the window title of X terminals
case ${TERM} in
xterm* | rxvt* | Eterm* | aterm | kterm | gnome* | interix | konsole*)
    PROMPT_COMMAND='echo -ne "\033]0;${USER}@${HOSTNAME%%.*}:${PWD/#$HOME/\~}\007"'
    ;;
screen*)
    PROMPT_COMMAND='echo -ne "\033_${USER}@${HOSTNAME%%.*}:${PWD/#$HOME/\~}\033\\"'
    ;;
esac

# Set colorful PS1 only on colorful terminals.
# dircolors --print-database uses its own built-in database
# instead of using /etc/DIR_COLORS.  Try to use the external file
# first to take advantage of user additions.  Use internal bash
# globbing instead of external grep binary.
safe_term=${TERM//[^[:alnum:]]/?} # sanitize TERM
match_lhs=""
[[ -f ~/.dir_colors ]] && match_lhs="${match_lhs}$(<~/.dir_colors)"
[[ -f /etc/DIR_COLORS ]] && match_lhs="${match_lhs}$(</etc/DIR_COLORS)"
[[ -z ${match_lhs} ]] && type -P dircolors >/dev/null &&
    match_lhs=$(dircolors --print-database)
[[ $'\n'${match_lhs} == *$'\n'"TERM "${safe_term}* ]]
if [[ "$EUID" == 0 ]]; then
    PS1='\[\033[01;31m\][\h\[\033[01;36m\] \W\[\033[01;31m\]]\$\[\033[00m\] '
else
    PS1='\[\033[01;35m\][\u@\h\[\033[01;37m\] \W\[\033[01;35m\]]\$\[\033[00m\] '
fi
unset safe_term match_lhs

# Bash won't get SIGWINCH if another process is in the foreground.
# Enable checkwinsize so that bash will check the terminal size when
# it regains control.  #65623
# http://cnswww.cns.cwru.edu/~chet/bash/FAQ (E11)
shopt -s checkwinsize
shopt -s expand_aliases
shopt -s histappend
shopt -s globstar

# Automatically activate or deactivate python virtualenvs
__python_venv() {
    # $VIRTUAL_ENV not set -- python virtualenv not activated, try to
    # activate it if '.env/bin/activate' or '.venv/bin/activate' exists
    if [[ -z "$VIRTUAL_ENV" ]]; then
        local path="$PWD"
        while [[ "$path" != "$(dirname "$path")" ]]; do
            for venv_dir in 'venv' 'env' '.venv' '.env'; do
                local activation_file="$path/$venv_dir/bin/activate"
                if [[ -f "$activation_file" ]]; then
                    source "$activation_file"
                    return
                fi
            done
            path="$(dirname "$path")"
        done
        return
    fi

    # $VIRTUAL_ENV set but 'deactivate' not found -- python virtualenv
    # activated in parent shell, try to activate in current shell if currently
    # in project directory or a subdirectory of the project directory
    local proj_dir="$(dirname "$VIRTUAL_ENV")"
    if ! __has deactivate; then
        if [[ "$PWD"/ == "$proj_dir"/* ]]; then
            local activation_file="$(echo "$VIRTUAL_ENV/bin/activate")"
            if [[ -f "$activation_file" ]]; then
                source "$activation_file"
            fi
            return
        fi
    fi

    # $VIRTUAL_ENV set and 'deactivate' found -- python virtualenv activated
    # in current shell, try to deactivate it if currently not inside the
    # project directory or a subdirectory of the project directory
    if [[ "$PWD"/ != "$proj_dir"/* ]] && __has deactivate; then
        deactivate
    fi
}
__python_venv

# Improved 'cd', automatically list directory contents and activate
# python virtualenvs
cd() {
    builtin cd "$@"
    if ! __has tput || ! __has wc; then
        ls -C --color
        __python_venv
        return
    fi

    local lines="$(tput lines)"
    local cols="$(tput cols)"
    local max_lines="$(($lines / 4))"
    local num_lines="$(ls -C --width="$cols" | wc -l)"
    if [[ "$num_lines" -le "$max_lines" ]]; then
        ls -C --color
        __python_venv
        return
    fi

    ls -C --color --width="$cols" | head -n "$max_lines"
    __python_venv
    echo
    echo "... $num_lines lines total"
}

# Clear scrollback in neovim terminal correctly
# See https://github.com/neovim/neovim/issues/21403
clear() {
    command clear "$@"
    if [[ -n "$NVIM" ]]; then
        nvim --clean --headless --server $NVIM \
            --remote-send "<Cmd>let scbk = &scbk | let &scbk = 1 | \
                let &scbk = scbk | unlet scbk<CR>" +'qa!' 2>/dev/null
    fi
}

__ff_open_files_or_dir() {
    # $@: files to open
    # Split targets into a list at newline
    local -a targets_list=()
    IFS=$'\n' read -rd '' -a targets_list <<<"$@"

    # If only one target and it is a directory, cd into it
    if [[ "${#targets_list[@]}" = 1 && -d "$targets_list[0]" ]]; then
        cd "$targets_list[0]"
        return $?
    fi

    # Copy text files and directories to a separate array and
    # use $EDITOR to open them; open other files with xdg-open
    local -a text_or_dirs=()
    local -a others=()
    for target in "${targets_list[@]}"; do
        if [[ -d "$target" || "$(file -b -- "$target")" =~ text|empty ]]; then
            text_or_dirs+=("$target")
        else
            others+=("$target")
        fi
    done

    if __has xdg-open; then
        for target in "${others[@]}"; do
            xdg-open "$target" >/dev/null 2>&1
        done
    elif [[ "${#others[@]}" > 0 ]]; then
        echo "xdg-open not found, omit opening files ${targets_list[@]}" >&2
    fi
    if (("${#text_or_dirs[@]}" > 0)); then
        __has "$EDITOR" && "$EDITOR" "${text_or_dirs[@]}" ||
            echo "\$EDITOR not found, omit opening files ${text_or_dirs[@]}" >&2
    fi
}

# Use fzf to open files or cd to directories
ff() {
    # $1: base directory
    # If there is only one target and it is a file, open it directly
    if (($# == 1)) && [[ -f "$1" ]]; then
        __ff_open_files_or_dir "$@"
        return
    fi

    # Exit if fzf or fd is not installed
    # On some systems, e.g. Ubuntu, fd executable is installed as 'fdfind'
    local fd_cmd=$(__has fd && echo fd || echo fdfind)
    if ! __has fzf || ! __has "$fd_cmd"; then
        echo 'fzf or fd is not installed' >&2
        return 1
    fi

    local tmpfile="$(mktemp)"
    local path="${1:-$PWD}"
    "$fd_cmd" -p -H -L -td -tf -tl --mount -c=always --search-path="$path" |
        fzf --ansi --query="$2" >$tmpfile

    local targets="$(cat "$tmpfile")"
    rm -f "$tmpfile"
    [[ -z "$targets" ]] && return 0

    __ff_open_files_or_dir "$targets"
    return
}

# Open nvim/vim/vi
v() {
    if __has nvim; then
        nvim "$@"
    elif __has vim; then
        vim "$@"
    elif __has vi; then
        vi "$@"
    else
        echo 'nvim/vim/vi not found' >&2
        return 1
    fi
}

# Aliases
alias sudoe="sudo -E "
alias cl="clear"
alias cp="cp -i" # confirm before overwriting something
alias x="trash"
alias g="git"
alias d="dot"
alias grep="grep --color"
alias egrep="egrep --color"
alias fgrep="fgrep --color"
alias ls="ls --color"
alias l="ls"
alias ll="ls -l"
alias lc="wc -l"
alias df="df -h"     # human-readable sizes
alias free="free -m" # show sizes in MB
alias tree="tree -N" # Display Chinese characters
alias nv="nvim"
alias vs="vim-startuptime"
alias clean-tmp="find /tmp -ctime +7 -exec rm -rf {} +"
# Save KDE plasma session
alias plasma-save-session="qdbus org.kde.ksmserver /KSMServer saveCurrentSession"

# Prevent Vim <Esc> lagging
bind 'set keyseq-timeout 1'

# Manage dotfiles
dot() {
    git --git-dir="$HOME/.dot" --work-tree="$HOME" "$@"
}
# Create remote branches (e.g. origin/master) on git fetch like normal repos
# See https://stackoverflow.com/questions/36410044/fetch-from-origin-in-bare-repository-in-git-does-not-create-remote-branch
dot config --local remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
# Set the path to the root of the working tree, make vim-fugitive's
# `:Gdiffsplit` work
dot config --local core.worktree "$HOME"
dot config --local status.showUntrackedFiles no

[[ -r '/usr/share/bash-completion/completions/git' ]] &&
    source '/usr/share/bash-completion/completions/git' &&
    __git_complete dot __git_main

[[ -r '/usr/share/bash-completion/bash_completion' ]] &&
    source '/usr/share/bash-completion/bash_completion'

# Source conda if it exists
[[ -r '/opt/miniconda3/etc/profile.d/conda.sh' ]] &&
    source '/opt/miniconda3/etc/profile.d/conda.sh'
