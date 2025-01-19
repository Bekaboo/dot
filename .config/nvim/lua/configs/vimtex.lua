if vim.env.TERM == 'linux' then
  vim.g.vimtex_syntax_conceal_disable = true
end

vim.g.vimtex_format_enabled = 1
vim.g.vimtex_imaps_enabled = 0
vim.g.vimtex_mappings_prefix = '<LocalLeader>l'
vim.g.vimtex_quickfix_ignore_filters = {
  [[Warning]],
  [[Overfull]],
  [[Underfull]],
  [[Font shape `.*' undefined]],
}

vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'tex', 'markdown' },
  group = vim.api.nvim_create_augroup('VimTexFileTypeInit', {}),
  callback = function(info)
    if info.match == 'markdown' then
      vim.api.nvim_eval('vimtex#init()')
      vim.api.nvim_eval('vimtex#text_obj#init_buffer()')
      vim.bo[info.buf].formatexpr = ''
    end
    -- Make surrounding delimiters large
    vim.keymap.set('n', 'css', vim.fn['vimtex#delim#add_modifiers'], {
      buffer = info.buf,
      desc = 'Surround with large delimiters',
    })
    -- Remove default `]]` mapping in insert mode as it causes lagging
    -- when typing `]`
    pcall(vim.keymap.del, 'i', ']]', {
      buffer = info.buf,
    })
  end,
})
