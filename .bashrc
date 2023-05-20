# ~/.bashrc
# vim: ft=sh ts=4 sw=4 sts=4 et :

[[ $- != *i* ]] && return

[ -r /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion

# Change the window title of X terminals
case ${TERM} in
    xterm*|rxvt*|Eterm*|aterm|kterm|gnome*|interix|konsole*)
        PROMPT_COMMAND='echo -ne "\033]0;${USER}@${HOSTNAME%%.*}:${PWD/#$HOME/\~}\007"'
        ;;
    screen*)
        PROMPT_COMMAND='echo -ne "\033_${USER}@${HOSTNAME%%.*}:${PWD/#$HOME/\~}\033\\"'
        ;;
esac

use_color=true

# Set colorful PS1 only on colorful terminals.
# dircolors --print-database uses its own built-in database
# instead of using /etc/DIR_COLORS.  Try to use the external file
# first to take advantage of user additions.  Use internal bash
# globbing instead of external grep binary.
safe_term=${TERM//[^[:alnum:]]/?}   # sanitize TERM
match_lhs=""
[[ -f ~/.dir_colors   ]] && match_lhs="${match_lhs}$(<~/.dir_colors)"
[[ -f /etc/DIR_COLORS ]] && match_lhs="${match_lhs}$(</etc/DIR_COLORS)"
[[ -z ${match_lhs}    ]] \
    && type -P dircolors >/dev/null \
    && match_lhs=$(dircolors --print-database)
[[ $'\n'${match_lhs} == *$'\n'"TERM "${safe_term}* ]] && use_color=true

if ${use_color} ; then
    # Enable colors for ls, etc. Prefer ~/.dir_colors
    if type -P dircolors >/dev/null ; then
        if [[ -f ~/.dir_colors ]] ; then
            eval $(dircolors -b ~/.dir_colors)
        elif [[ -f /etc/DIR_COLORS ]] ; then
            eval $(dircolors -b /etc/DIR_COLORS)
        fi
    fi

    if [[ ${EUID} == 0 ]] ; then
        PS1='\[\033[01;31m\][\h\[\033[01;36m\] \W\[\033[01;31m\]]\$\[\033[00m\] '
    else
        PS1='\[\033[01;35m\][\u@\h\[\033[01;37m\] \W\[\033[01;35m\]]\$\[\033[00m\] '
    fi

    alias ls='ls --color=auto'
    alias grep='grep --colour=auto'
    alias egrep='egrep --colour=auto'
    alias fgrep='fgrep --colour=auto'
else
    if [[ ${EUID} == 0 ]] ; then
        # show root@ when we don't have colors
        PS1='\u@\h \W \$ '
    else
        PS1='\u@\h \w \$ '
    fi
fi

unset use_color safe_term match_lhs sh

xhost +local:root > /dev/null 2>&1

# Bash won't get SIGWINCH if another process is in the foreground.
# Enable checkwinsize so that bash will check the terminal size when
# it regains control.  #65623
# http://cnswww.cns.cwru.edu/~chet/bash/FAQ (E11)
shopt -s checkwinsize

shopt -s expand_aliases

# export QT_SELECT=4

# Enable history appending instead of overwriting.  #139609
shopt -s histappend

# TTY Terminal Colors
if [ "$TERM" = "linux" ]; then
    echo -en "\e]P0000000" #black
    echo -en "\e]P82B2B2B" #darkgrey
    echo -en "\e]P1D75F5F" #darkred
    echo -en "\e]P9E33636" #red
    echo -en "\e]P287AF5F" #darkgreen
    echo -en "\e]PA98E34D" #green
    echo -en "\e]P3D7AF87" #brown
    echo -en "\e]PBFFD75F" #yellow
    echo -en "\e]P48787AF" #darkblue
    echo -en "\e]PC7373C9" #blue
    echo -en "\e]P5BD53A5" #darkmagenta
    echo -en "\e]PDD633B2" #magenta
    echo -en "\e]P65FAFAF" #darkcyan
    echo -en "\e]PE44C9C9" #cyan
    echo -en "\e]P7E5E5E5" #lightgrey
    echo -en "\e]PEEEEEEE" #white
    clear #for background artifacting
fi

# 'less' highlights
export LESS_TERMCAP_mb=$'\e[1;32m'
export LESS_TERMCAP_md=$'\e[1;32m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[01;33m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;4;34m'

# Automatically activate or deactivate python virtualenvs
pyenv() {
    local activation_file=""
    # $VIRTUAL_ENV not set -- python virtualenv not activated, try to
    # activate it if '.env/bin/activate' or '.venv/bin/activate' exists
    if [[ -z "$VIRTUAL_ENV" ]]; then
        if [[ -e ./.env/bin/activate ]]; then
            activation_file="./.env/bin/activate"
        elif [[ -e ./.venv/bin/activate ]]; then
            activation_file="./.venv/bin/activate"
        fi
        if [[ -n "$activation_file" ]]; then
            chmod +x "$activation_file"
            source "$activation_file"
        fi
        return
    fi

    # $VIRTUAL_ENV set but 'deactivate' not found -- python virtualenv
    # activated in parent shell, try to activate in current shell if currently
    # in project directory or a subdirectory of the project directory
    local parent_dir="$(dirname "$VIRTUAL_ENV")"
    if [[ -z "$(command -v deactivate)" ]]; then
        if [[ "$PWD"/ == "$parent_dir"/* ]]; then
            activation_file="$(command -v activate)"
            chmod +x "$activation_file"
            source "$activation_file"
            return
        fi
    fi

    # $VIRTUAL_ENV set and 'deactivate' found -- python virtualenv activated
    # in current shell, try to deactivate it if currently not inside the
    # project directory or a subdirectory of the project directory
    if [[ "$PWD"/ != "$parent_dir"/* ]]; then
        deactivate
    fi
}

# 'cd' improved, 'cd' and 'ls', then automatically activate or deactivate
# python virtualenvs
cdim() {
    builtin cd "$@" && ls --color=auto;
    pyenv
}

# Aliases
alias sudo="sudo -E "
alias cd="cdim"
alias cp="cp -i"        # confirm before overwriting something
alias rm="\\trash"
alias l="ls"
alias ll="ls -l"
alias df="df -h"        # human-readable sizes
alias free="free -m"    # show sizes in MB
alias tree="tree -N"    # Display Chinese characters
alias clip="xclip -sel clip"
alias lzgit="lazygit"
alias pip-install="pip install --user"
alias translate="trans -shell -b -no-auto :zh"
alias etalsnart="trans -shell -b -no-auto :en"
alias nv="nvim"
alias v="nvim"
alias vi="nvim --clean"
alias vs="vim-startuptime"
alias emacs="emacs -nw"
alias em="emacs -nw"
alias r=". ranger"
alias winecfg-wechat="/opt/apps/com.qq.weixin.deepin/files/run.sh winecfg"
alias home-backup="borg create \
    --list -v \
    --exclude-from ~/.scripts/borg/exclude.txt \
    borg/home::{hostname}-{user}-{now:%Y-%m-%dT%H:%M:%S.%f} ~; \
    borg prune --list -d 60 -w 24 -m 24 -y 10 borg/home; \
    borg compact --cleanup-commits borg/home"
alias kde-restart="kquitapp5 plasmashell || kstart5 plasmashell"
alias kwin-restart="kwin_x11 --replace 2>/dev/null &"
alias clean-tmp="find /tmp -ctime +7 -exec rm -rf {} +"
# Save KDE plasma session
alias plasma-save-session="qdbus org.kde.ksmserver /KSMServer saveCurrentSession"

# Manage dotfiles
dot() {
    /usr/bin/git --git-dir="$HOME/.dot" --work-tree="$HOME" "$@"
}
source "/usr/share/bash-completion/completions/git"
__git_complete dot __git_main
dot config --local status.showUntrackedFiles no
# dfiles config --local filter.plasma_appletsrc_filter.clean "sed '/popupWidth=\|popupHeight=\|PreloadWeight=/d'"
# dfiles config --local filter.plasma_appletsrc_filter.smudge "sed '/popupWidth=\|popupHeight=\|PreloadWeight=/d'"
# dfiles config --local filter.plasma_scale_filter.clean "sed '/forceFontDPI=\|ScaleFactor=\|ScreenScaleFactors=/d'"
# dfiles config --local filter.plasma_scale_filter.smudge "sed '/forceFontDPI=\|ScaleFactor=\|ScreenScaleFactors=/d'"
# dfiles config --local filter.plasma_cursor_size_filter.clean "sed '/cursorSize=\|cursor-theme-size=/d'"
# dfiles config --local filter.plasma_cursor_size_filter.smudge "sed '/cursorSize=\|cursor-theme-size=/d'"

# Prevent Vim <Esc> lagging
bind 'set keyseq-timeout 1'

# Add execution permission to scripts
if [[ -d ~/.scripts ]]; then
    chmod +x ~/.scripts/*
fi

# Automatically enable or disable python virtualenvs
pyenv
