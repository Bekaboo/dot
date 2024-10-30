local opts = {
  headline_highlights = {},
  codeblock_highlight = 'CodeBlock',
  quote_string = vim.g.modern_ui and '┃' or '│',
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
  local hl = require('utils.hl')
  hl.set(0, 'CodeBlock', { bg = 'CursorLine' })
  hl.set(0, 'markdownCode', { bg = 'CursorLine', fg = 'markdownCode' })
  hl.set(0, '@markup.raw.markdown_inline', {
    bg = 'CursorLine',
    fg = 'markdownCode',
  })
end
set_default_hlgroups()

vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('HeadlinesSetDefaultHlGroups', {}),
  desc = 'Set default highlight groups for headlines.nvim.',
  callback = set_default_hlgroups,
})
