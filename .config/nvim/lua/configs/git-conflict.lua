---@diagnostic disable-next-line: missing-fields
require('git-conflict').setup({
  disable_diagnostics = true,
  default_mappings = {
    ours = 'c<',
    theirs = 'c>',
    none = 'c-',
    both = 'c=',
    next = ']x',
    prev = '[x',
  },
})

---Set default hl for git-conflict.nvim
---
---Git conflict by default only use background color of `hl-DiffText` or
---`hl-DiffAdd` for conflict text. This does not play well with colorschemes
---using intense bg color and reversed fg color for diff text.
---@return nil
local function set_default_hlgroups()
  vim.api.nvim_set_hl(0, 'GitConflictCurrent', { link = 'DiffText' })
  vim.api.nvim_set_hl(0, 'GitConflictIncoming', { link = 'DiffAdd' })
  vim.api.nvim_set_hl(0, 'GitConflictAncestor', { link = 'DiffText' })
end
set_default_hlgroups()

vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('my.git-conflict', {}),
  desc = 'Set default highlight groups for git-conflict.nvim.',
  callback = set_default_hlgroups,
})
