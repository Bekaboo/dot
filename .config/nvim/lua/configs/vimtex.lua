if vim.env.TERM == 'linux' then
  vim.g.vimtex_syntax_conceal_disable = true
end

-- Disable vimtex warning about highlighting if we have latex treesitter parser
-- as we can use treesitter instead of vimtex for latex mathzone detection, see
-- https://github.com/lervag/vimtex/issues/2469#issuecomment-1446685300
if pcall(vim.treesitter.get_parser, nil, 'latex') then
  vim.g.vimtex_syntax_enabled = 0
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
