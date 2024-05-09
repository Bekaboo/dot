# fzf settings for fish

if not type -q fzf_key_bindings
    return
end

if type -q fd
    set -gx FZF_CTRL_T_COMMAND "fd -p -H -L -td -tf -tl --mount \
        -c=always --search-path=\$dir"
    set -gx FZF_ALT_C_COMMAND "fd -p -H -L -td --mount \
        -c=always --search-path=\$dir"
else if type -q fdfind
    set -gx FZF_CTRL_T_COMMAND "fdfind -p -H -L -td -tf -tl --mount \
        -c=always --search-path=\$dir"
    set -gx FZF_ALT_C_COMMAND "fdfind -p -H -L -td --mount \
        -c=always --search-path=\$dir"
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
        -o -path '*node_modules/*' \
        -o -path '*vendor/*'       \
        -o -path '*venv/*'         \
        -o -fstype 'sysfs'         \
        -o -fstype 'devfs'         \
        -o -fstype 'devtmpfs'      \
        -o -fstype 'proc' \\) -prune \
    -o -type d -print 2> /dev/null | sed 's@^\./@@'"
end

fzf_key_bindings
