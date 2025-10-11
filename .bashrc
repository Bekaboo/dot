#!/usr/bin/env bash
# ~/.bashrc
# vim:ft=sh:et:ts=4:sw=4:sts=4:

has() {
    command -v "$1" >/dev/null 2>&1
}

if [[ -r "$HOME/.bash_envvars" ]]; then
    source "$HOME/.bash_envvars"
fi

[[ $- != *i* ]] && return

# Start setting up ble.sh
# https://github.com/akinomyoga/ble.sh?tab=readme-ov-file#set-up-bashrc
for ble_install_path in /usr/share ~/.local/share; do
    if [[ -r "$ble_install_path/blesh/ble.sh" ]]; then
        source -- "$ble_install_path/blesh/ble.sh" --attach=none
        break
    fi
done

# Prompt configuration
PS1='\[\033[01;3'$( ((EUID)) && echo 5 || echo 1)'m\][\u@\h\[\033[01;37m\] \W\[\033[01;3'$( ((EUID)) && echo 5 || echo 1)'m\]]\$\[\033[00m\] '

# OSC133 support
# Source: https://codeberg.org/dnkl/foot/wiki#bash-2
__cmd_done() {
    printf '\e]133;D\e\\'
}
PS0+='\e]133;C\e\\'
PROMPT_COMMAND=${PROMPT_COMMAND:+$PROMPT_COMMAND; }__cmd_done

# Bash won't get SIGWINCH if another process is in the foreground.
# Enable checkwinsize so that bash will check the terminal size when
# it regains control.  #65623
# http://cnswww.cns.cwru.edu/~chet/bash/FAQ (E11)
shopt -s checkwinsize &>/dev/null
shopt -s expand_aliases &>/dev/null
shopt -s histappend &>/dev/null
shopt -s globstar &>/dev/null # not supported by bash on macOS

# Prevent Vim <Esc> lagging
bind 'set keyseq-timeout 1'

# Common aliases
alias cl='clear'
alias x='trash'
alias xr='trash-restore'
alias g='git'
alias d='dot'
alias ll='ls -lhA'
alias kc='kubectl'
alias tf='terraform'

# Fzf keybindings and completion
[[ -r /usr/share/fzf/key-bindings.bash ]] && . /usr/share/fzf/key-bindings.bash
[[ -r /usr/share/fzf/completion.bash ]] && . /usr/share/fzf/completion.bash

__ff_open_files_or_dir() {
    # $@: files to open
    # Split targets into a list at newline
    local -a targets_list=()
    IFS=$'\n' read -rd '' -a targets_list <<<"$@"

    # If only one target and it is a directory, cd into it
    if [[ "${#targets_list[@]}" = 1 && -d "${targets_list[0]}" ]]; then
        cd "${targets_list[0]}" || return
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

    if has xdg-open; then
        for target in "${others[@]}"; do
            xdg-open "$target" >/dev/null 2>&1
        done
    elif (("${#others[@]}" > 0)); then
        echo "xdg-open not found, omit opening files:" "${targets_list[@]}" >&2
    fi
    if (("${#text_or_dirs[@]}" > 0)); then
        "$EDITOR" "${text_or_dirs[@]}"
    fi
}

# Use fzf to open files or cd to directories
ff() {
    # $1: base directory
    # $2: optional initial query
    local -r path=${1:-$PWD}
    local -r query=$2

    # If there is only one target and it is a file, open it directly
    if (($# == 1)) && [[ -f "$path" ]]; then
        __ff_open_files_or_dir "$@"
        return
    fi

    if ! has fzf; then
        echo 'fzf is not executable' >&2
        return 1
    fi

    local -r tmpfile=$(mktemp)
    trap 'rm -f "$tmpfile"' EXIT INT TERM HUP

    # On some systems, e.g. Ubuntu, fd executable is installed as 'fdfind'
    local -r fd_cmd=$(has fd && echo fd || echo fdfind)
    if has "$fd_cmd"; then
        "$fd_cmd" -0 -p -H -L -td -tf -tl -c=always --search-path="$path" |
            fzf --read0 --ansi --query="$query" >"$tmpfile"
    elif has find; then
        find "$path" -print0 -type d -o -type f -o -type l -follow |
            fzf --read0 --ansi --query="$query" >"$tmpfile"
    else
        echo 'fd/find is not executable' >&2
        return 1
    fi

    local -r targets=$(cat "$tmpfile")
    if [[ -z "$targets" ]]; then
        return 0
    fi

    __ff_open_files_or_dir "$targets"
    return
}

# Open nvim/vim/vi
v() {
    for vim_cmd in nvim vim vi; do
        if has "$vim_cmd"; then
            "$vim_cmd" "$@"
            return
        fi
    done
    echo 'nvim/vim/vi not found' >&2
    return 1
}

# Clear both screen and all previous outputs, works on Linux & macOS, see:
# https://stackoverflow.com/questions/2198377/how-can-i-clear-previous-output-in-terminal-in-mac-os-x
clear() {
    printf '\33c\e[3J'
}

# Manage dotfiles
dot() {
    git --git-dir="$DOT_DIR" --work-tree="$HOME" "$@"
}

# Create remote branches (e.g. origin/master) on git fetch like normal repos
# See https://stackoverflow.com/questions/36410044/fetch-from-origin-in-bare-repository-in-git-does-not-create-remote-branch
dot config --local remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'

# Set the path to the root of the working tree, make vim-fugitive's
# `:Gdiffsplit` work
dot config --local core.worktree "$HOME"

# Fix error: 'warning: core.bare and core.worktree do not make sense' when
# using fugitive in nvim to stage files managed by dotfiles bare repo
# https://stackoverflow.com/questions/11856690/setting-the-work-tree-of-each-bare-repo
dot config --local core.bare false

# Don't list untracked files on `dot status`
dot config --local status.showUntrackedFiles no

# Complete `dot` command with `git` subcommands, also fix git completion on macOS
for git_cmp in \
    /usr/share/bash-completion/completions/git \
    /Applications/Xcode.app/Contents/Developer/usr/share/git-core/git-completion.bash; do
    if [[ -r "$git_cmp" ]]; then
        source "$git_cmp" && __git_complete dot __git_main
        break
    fi
done

# List current directory on directory change, see `__post_cd` below
__autols() {
    local -r output=$(ls -C --color)

    if [[ -z "$output" ]]; then
        return
    fi

    local max_lines=4
    local num_lines=4

    if has tput && has wc; then
        local -r lines=$(tput lines)
        local -r max_lines=$((lines / 4))
        local -r num_lines=$(printf '%s\n' "$output" | wc -l | xargs) # trim whitespaces
    fi

    if [[ "$num_lines" -le "$max_lines" ]]; then
        printf '%s\n' "$output"
    else
        printf '%s\n' "$output" | head -n "$max_lines"
        echo
        echo "... $num_lines lines total"
    fi
}

# Python setup
# Automatically activate or deactivate python virtualenvs
__python_venv() {
    local path=$PWD
    while [[ "$path" != "$(dirname "$path")" ]]; do
        for venv_dir in 'venv' 'env' '.venv' '.env'; do
            local activation_file=$path/$venv_dir/bin/activate
            if [[ -f "$activation_file" ]]; then
                source "$activation_file"
                return
            fi
        done
        path="$(dirname "$path")"
    done

    if [[ -n "$VIRTUAL_ENV" ]] && has deactivate; then
        deactivate
    fi
}
__python_venv

# Track directory changes and run post-cd actions
__prev_dir=$PWD
__post_cd() {
    if [[ "$PWD" == "$__prev_dir" ]]; then
        return
    fi
    __prev_dir=$PWD

    __autols
    __python_venv
}

PROMPT_COMMAND=${PROMPT_COMMAND:+$PROMPT_COMMAND; }__post_cd

# Setup pyenv, see:
# - `~/.profile`
# - https://github.com/pyenv/pyenv?tab=readme-ov-file#bash
if has pyenv; then
    eval "$(pyenv init - bash)"
fi

# Setup miniconda
[[ -r /opt/miniconda3/etc/profile.d/conda.sh ]] &&
    source /opt/miniconda3/etc/profile.d/conda.sh

# Setup zoxide
if has zoxide; then
    eval "$(zoxide init bash)"
fi

# End setting up ble.sh
if [[ "${BLE_VERSION-}" ]] && has ble-attach; then
    ble-attach
fi
