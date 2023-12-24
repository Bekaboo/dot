# Clear scrollback in neovim terminal correctly
# See https://github.com/neovim/neovim/issues/21403
function clear --wraps clear \
    --description 'Clear scrollback in neovim terminal correctly'
    command clear $argv
    if test -n $NVIM
        nvim --clean --headless --server $NVIM \
            --remote-send "<Cmd>let scbk = &scbk | let &scbk = 1 | \
                let &scbk = scbk | unlet scbk<CR>" +'qa!' 2>/dev/null
    end
end
