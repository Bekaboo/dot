if not status is-interactive
    exit
end

# Fzf envrionment variables
set -gx FZF_DEFAULT_OPTS "--reverse \
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
    --bind=alt-up:first,alt-down:last \
    --bind=shift-up:preview-up,shift-down:preview-down \
    --bind=alt-v:preview-half-page-up,ctrl-v:preview-half-page-down"

# If supports 256 colors
if not type -q tput; or test (tput colors 2>/dev/null) -lt 256
    set -gxa FZF_DEFAULT_OPTS --no-unicode '--marker=+\ ' '--pointer=\>\ '
end

if type -q fd
    set -gx FZF_CTRL_T_COMMAND "fd -p -H -L -td -tf -tl -c=always --search-path=\$dir"
    set -gx FZF_ALT_C_COMMAND "fd -p -H -L -td -c=always --search-path=\$dir"
else if type -q fdfind
    set -gx FZF_CTRL_T_COMMAND "fdfind -p -H -L -td -tf -tl -c=always --search-path=\$dir"
    set -gx FZF_ALT_C_COMMAND "fdfind -p -H -L -td -c=always --search-path=\$dir"
else
    set -gx FZF_CTRL_T_COMMAND "find -L \$dir -mindepth 1 \\( \
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
    set -gx FZF_ALT_C_COMMAND "find -L \$dir -mindepth 1 \\( \
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
set -gx FZF_DEFAULT_COMMAND $FZF_CTRL_T_COMMAND
set -gx FZF_CTRL_R_OPTS --no-preview
set -gx FZF_PREVIEW_DISABLE_UB true # Disable ueberzug preview

if type -q fzf_key_bindings
    fzf_key_bindings
end

# Fzf.fish plugin configs
# Use custom previewer script if available
if type -q fzf-file-previewer
    set -gx fzf_preview_dir_cmd fzf-file-previewer
    set -gx fzf_preview_file_cmd fzf-file-previewer
end

# Include hidden files
set fzf_fd_opts -p -H -L -td -tf -tl -c=always

# Fzf keybindings
if type -q fzf_configure_bindings
    fzf_configure_bindings --git_status=\e\cg --git_stash=\e\cs
end
