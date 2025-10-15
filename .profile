#!/usr/bin/env sh
# ~/.profile
# vim:ft=sh:et:ts=4:sw=4:sts=4:

has() {
    command -v "$1" >/dev/null 2>&1
}

# macOS homebrew install paths
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if has brew; then
    eval "$(brew shellenv)"
fi

# Setup pyenv, see:
# https://github.com/pyenv/pyenv?tab=readme-ov-file#b-set-up-your-shell-environment-for-pyenv
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"

# Local executables
export PATH="$HOME/go/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.bin:$PATH"

# Dotfile bare repo path
export DOT_DIR="$HOME/.dot"

if [ -r "$HOME/.envvars" ]; then
    . "$HOME/.envvars"
fi

# Setup default editor
for editor in nvim vim vi; do
    if has "$editor"; then
        export EDITOR="$editor"
        [ "$editor" = nvim ] && export MANPAGER='nvim +Man!'
        break
    fi
done

# Set rg config path
export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"

export BAT_THEME=ansi

# Fzf configuration
# shellcheck disable=SC2089
# we want to include '' (single quotes) in `--preview` option because opts are
# parsed twice when passing to fzf
#
# Set gutter to space to hide gutter:
# https://github.com/junegunn/fzf/blob/master/CHANGELOG.md#hiding-the-gutter-column
export FZF_DEFAULT_OPTS="--reverse \
    --preview='fzf-file-previewer {}' \
    --preview-window=right,55%,border-none,nocycle \
    --info=inline-right \
    --no-separator \
    --no-scrollbar \
    --border=none \
    --margin=1,0,0 \
    --height=~75% \
    --min-height=16 \
    --scroll-off=999 \
    --multi \
    --ansi \
    --color=fg:-1,bg:-1,hl:bold:cyan \
    --color=fg+:-1,bg+:-1,hl+:bold:cyan \
    --color=border:white,preview-border:white \
    --color=marker:bold:cyan,prompt:bold:red,pointer:bold:red \
    --color=gutter:grey,info:bold:red,spinner:cyan,header:white \
    --bind=ctrl-k:kill-line \
    --bind=alt-a:toggle-all \
    --bind=alt-up:first,alt-down:last \
    --bind=shift-up:preview-up,shift-down:preview-down \
    --bind=alt-v:preview-half-page-up,ctrl-v:preview-half-page-down"

fd=$(has fd && echo fd || echo fdfind)

if has "$fd"; then
    export FZF_DEFAULT_COMMAND="$fd -p -H -L -td -tf -tl -c=always"
    export FZF_ALT_C_COMMAND="$fd -p -H -L -td -c=always"
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

export FZF_CTRL_R_OPTS=--no-preview
export FZF_PREVIEW_DISABLE_UB=true # Disable ueberzug preview

# Ensure color theme files are correctly linked
has setbg && ( setbg & ) 2>/dev/null
has setcolors && ( setcolors & ) 2>/dev/null

# Automatically login to proot distro on termux
if has proot-distro &&
    [ -n "$PROOT_DISTRO" ] &&
    [ -n "$PROOT_USER" ] &&
    [ -n "$TERMUX_VERSION" ]; then
    exec proot-distro login "$PROOT_DISTRO" --user "$PROOT_USER" --termux-home
fi

# Greeting message
if [ ! -e "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/greeted" ]; then
    touch "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/greeted"

    if has fastfetch; then
        fetch=fastfetch
    elif has neofetch; then
        fetch=neofetch
    fi

    if [ -n "$fetch" ]; then
        # Run in pseudo-terminal to prevent terminal state issues
        # (tmux error: 'not a terminal', etc)
        # macOS `script` does not accept `-c` flag
        if script -q /dev/null -c exit >/dev/null 2>&1; then
            script -q /dev/null -c "$fetch"
        else
            script -q /dev/null "$fetch"
        fi
    fi
fi
