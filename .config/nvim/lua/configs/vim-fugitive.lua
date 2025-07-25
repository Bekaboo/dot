-- Override the default fugitive commands to save the previous buffer
-- before opening the log window.
vim.cmd([[
  command! -bang -nargs=? -range=-1 -complete=customlist,fugitive#LogComplete Gclog let g:fugitive_prevbuf=bufnr() | exe fugitive#LogCommand(<line1>,<count>,+"<range>",<bang>0,"<mods>",<q-args>, "c")
  command! -bang -nargs=? -range=-1 -complete=customlist,fugitive#LogComplete GcLog let g:fugitive_prevbuf=bufnr() | exe fugitive#LogCommand(<line1>,<count>,+"<range>",<bang>0,"<mods>",<q-args>, "c")
  command! -bang -nargs=? -range=-1 -complete=customlist,fugitive#LogComplete Gllog let g:fugitive_prevbuf=bufnr() | exe fugitive#LogCommand(<line1>,<count>,+"<range>",<bang>0,"<mods>",<q-args>, "l")
  command! -bang -nargs=? -range=-1 -complete=customlist,fugitive#LogComplete GlLog let g:fugitive_prevbuf=bufnr() | exe fugitive#LogCommand(<line1>,<count>,+"<range>",<bang>0,"<mods>",<q-args>, "l")
]])

-- stylua: ignore start
vim.keymap.set('n', '<Leader>gd', '<Cmd>Gdiff<CR>', { desc = 'Git diff current file' })
vim.keymap.set('n', '<Leader>gD', '<Cmd>Git diff<CR>', { desc = 'Git diff entire repo' })
vim.keymap.set('n', '<Leader>gB', '<Cmd>Git blame<CR>', { desc = 'Git blame current file' })
vim.keymap.set('n', '<Leader>gl', '<Cmd>Git log -100 --oneline --follow -- %<CR>', { desc = 'Git log current file' })
vim.keymap.set('n', '<Leader>gL', '<Cmd>Git log -100 --oneline --graph<CR>', { desc = 'Git log entire repo' })
-- stylua: ignore end

local groupid = vim.api.nvim_create_augroup('FugitiveSettings', {})
vim.api.nvim_create_autocmd('User', {
  pattern = 'FugitiveIndex',
  group = groupid,
  callback = function(args)
    vim.keymap.set({ 'n', 'x' }, 'S', 's', { buffer = args.buf, remap = true })
    vim.keymap.set({ 'n', 'x' }, 'x', 'X', { buffer = args.buf, remap = true })
    vim.keymap.set({ 'n', 'x' }, '[g', '[c', {
      desc = 'Go to previous hunk',
      buffer = args.buf,
      remap = true,
    })
    vim.keymap.set({ 'n', 'x' }, ']g', ']c', {
      desc = 'Go to next hunk',
      buffer = args.buf,
      remap = true,
    })
  end,
})

vim.api.nvim_create_autocmd('User', {
  pattern = 'FugitiveObject',
  group = groupid,
  callback = function()
    -- stylua: ignore start
    local goto_next = [[<Cmd>silent! exe "if get(getloclist(0, {'winid':''}), 'winid', 0) | exe v:count.'lne' | else | exe v:count.'cn' | endif"<CR>]]
    local goto_prev = [[<Cmd>silent! exe "if get(getloclist(0, {'winid':''}), 'winid', 0) | exe v:count.'lpr' | else | exe v:count.'cp' | endif"<CR>]]
    -- stylua: ignore end
    vim.keymap.set('n', '<C-n>', goto_next, { buffer = true })
    vim.keymap.set('n', '<C-p>', goto_prev, { buffer = true })
    vim.keymap.set('n', '<C-j>', goto_next, { buffer = true })
    vim.keymap.set('n', '<C-k>', goto_prev, { buffer = true })
    vim.keymap.set('n', '<C-^>', function()
      if vim.g.fugitive_prevbuf then
        vim.cmd.cclose()
        vim.cmd.lclose()
        vim.cmd.buffer(vim.g.fugitive_prevbuf)
        vim.g.fugitive_prevbuf = nil
        vim.cmd.bw({ '#', bang = true, mods = { emsg_silent = true } })
      end
    end, { buffer = true })
  end,
})

vim.api.nvim_create_autocmd('BufEnter', {
  desc = 'Ensure that fugitive buffers are not listed and are wiped out after hidden.',
  group = groupid,
  pattern = 'fugitive://*',
  callback = function(args)
    vim.bo[args.buf].buflisted = false
  end,
})

vim.api.nvim_create_autocmd('FileType', {
  desc = 'Set buffer-local options for fugitive buffers.',
  group = groupid,
  pattern = 'fugitive',
  callback = function()
    vim.opt_local.winbar = nil
    vim.opt_local.signcolumn = 'no'
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
  end,
})

vim.api.nvim_create_autocmd('FileType', {
  desc = 'Set buffer-local options for fugitive blame buffers.',
  group = groupid,
  pattern = 'fugitiveblame',
  callback = function()
    local win_alt = vim.fn.win_getid(vim.fn.winnr('#'))
    vim.opt_local.winbar = vim.api.nvim_win_is_valid(win_alt)
        and vim.wo[win_alt].winbar ~= ''
        and ' '
      or ''

    vim.opt_local.number = false
    vim.opt_local.signcolumn = 'no'
    vim.opt_local.relativenumber = false
  end,
})
