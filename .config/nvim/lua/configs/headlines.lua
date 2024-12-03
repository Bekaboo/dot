local opts = {
  headline_highlights = {},
  codeblock_highlight = 'CodeBlock',
  quote_string = vim.go.termguicolors and '┃' or '│',
  fat_headlines = false,
}

require('headlines').setup({
  markdown = opts,
  norg = opts,
  org = opts,
  rmd = opts,
})

---Set default highlight groups for headlines.nvim
---@return nil
local function set_default_hlgroups()
  require('utils.hl').set(0, 'CodeBlock', { bg = 'CursorLine' })
end
set_default_hlgroups()

vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('HeadlinesSetDefaultHlGroups', {}),
  desc = 'Set default highlight groups for headlines.nvim.',
  callback = set_default_hlgroups,
})
