if vim.env.TERM == 'linux' then
  vim.g.vimtex_syntax_conceal_disable = true
end

-- Enable vim's legacy regex-based syntax highlighting alongside treesitter
-- highlighting for some vimtex functions, e.g. changing modifiers, formatting,
-- indentation, etc.
if pcall(vim.treesitter.get_parser, nil, 'latex') then
  vim.treesitter.start = (function(cb)
    ---@param bufnr integer? Buffer to be highlighted (default: current buffer)
    ---@param lang string? Language of the parser (default: from buffer filetype)
    return function(bufnr, lang, ...)
      bufnr = vim._resolve_bufnr(bufnr)
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      cb(bufnr, lang, ...)
      -- Re-enable regex syntax highlighting after starting treesitter
      if vim.bo[bufnr].ft == 'tex' or lang == 'latex' then
        vim.bo[bufnr].syntax = 'on'
      end
    end
  end)(vim.treesitter.start)
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
