if vim.env.TERM == 'linux' then
  vim.g.vimtex_syntax_conceal_disable = true
end

vim.g.vimtex_quickfix_mode = 0
vim.g.vimtex_format_enabled = 1
vim.g.vimtex_imaps_enabled = 0
vim.g.vimtex_mappings_prefix = '<LocalLeader>l'

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'tex',
  group = vim.api.nvim_create_augroup('VimTexFileTypeInit', {}),
  callback = function(args)
    -- Make surrounding delimiters large
    vim.keymap.set('n', 'css', vim.fn['vimtex#delim#add_modifiers'], {
      buffer = args.buf,
      desc = 'Surround with large delimiters',
    })
    -- Remove default `]]` mapping in insert mode as it causes lagging
    -- when typing `]`
    pcall(vim.keymap.del, 'i', ']]', {
      buffer = args.buf,
    })
  end,
})
