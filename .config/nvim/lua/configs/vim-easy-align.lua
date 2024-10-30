vim.g.easy_align_delimiters = {
  ['\\'] = {
    pattern = [[\\\+]],
  },
  ['/'] = {
    pattern = [[//\+\|/\*\|\*/]],
    delimiter_align = 'c',
    ignore_groups = '!Comment',
  },
}

-- stylua: ignore start
vim.keymap.set({ 'n', 'x' }, 'gl', '<Plug>(EasyAlign)', { noremap = false })
vim.keymap.set({ 'n', 'x' }, 'gL', '<Plug>(LiveEasyAlign)', { noremap = false })
-- stylua: ignore end
