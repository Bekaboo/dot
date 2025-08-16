-- Install parsers shipped with neovim to avoid unmatched parsers
-- (shipped with neovim) and query files (provided by nvim-treesitter)
require('nvim-treesitter').install({
  'c',
  'lua',
  'vim',
  'bash',
  'query',
  'python',
  'vimdoc',
  'markdown',
  'markdown_inline',
})
