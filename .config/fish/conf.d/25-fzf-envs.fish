# Set fzf environment variables only once on login for performance
if not status is-login
    exit
end

# Fzf environment variables
#
# Set gutter to space to hide gutter:
# https://github.com/junegunn/fzf/blob/master/CHANGELOG.md#hiding-the-gutter-column
set -Ux FZF_DEFAULT_OPTS "--reverse \
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

# Disable ueberzug preview
set -Ux FZF_PREVIEW_DISABLE_UB true

# Setup official fzf fish plugin provided by
# https://github.com/junegunn/fzf/blob/master/shell/key-bindings.fish
set -l fd (type -q fd; and echo fd; or echo fdfind)
if type -q $fd
    set -Ux FZF_CTRL_T_COMMAND "$fd -p -H -L -td -tf -tl -c=always --search-path=\$dir"
    set -Ux FZF_ALT_C_COMMAND "$fd -p -H -L -td -c=always --search-path=\$dir"
else
    set -Ux FZF_CTRL_T_COMMAND "find -L \$dir -mindepth 1 \\( \
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
        -o -path '*.env/*'         \
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
    -o -type l -print 2> /dev/null | sed 's@^\./@@'"

    set -Ux FZF_ALT_C_COMMAND "find -L \$dir -mindepth 1 \\( \
        -Uath '*%*'                \
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
        -o -path '*env/*'          \
        -o -path '*cache*/*'       \
        -o -path '*dosdevices/*'   \
        -o -path '*node_modules/*' \
        -o -path '*vendor/*'       \
        -o -path '*venv/*'         \
        -o -fstype 'sysfs'         \
        -o -fstype 'devfs'         \
        -o -fstype 'devtmpfs'      \
        -o -fstype 'proc' \\) -prune \
    -o -type d -print 2> /dev/null | sed 's@^\./@@'"
end

set -Ux FZF_CTRL_R_OPTS --no-preview
set -Ux FZF_DEFAULT_COMMAND $FZF_CTRL_T_COMMAND

# Setup 3rd-party fzf.fish plugin
# https://github.com/PatrickF1/fzf.fish
# Use custom previewer script if available
if type -q fzf-file-previewer
    set -Ux fzf_preview_dir_cmd fzf-file-previewer
    set -Ux fzf_preview_file_cmd fzf-file-previewer
end

# Include hidden files
set -Ux fzf_fd_opts -p -H -L -td -tf -tl -c=always
