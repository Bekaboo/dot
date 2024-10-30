local tsj = require('treesj')

tsj.setup({
  use_default_keymaps = false,
  max_join_length = 1024,
})

---@param preset table?
---@return nil
function _G.tsj_split_recursive(_, preset)
  require('treesj.format')._format(
    'split',
    vim.tbl_deep_extend('force', preset or {}, {
      split = { recursive = true },
    })
  )
end

---@param preset table?
---@return nil
function _G.tsj_toggle_recursive(_, preset)
  require('treesj.format')._format(
    nil,
    vim.tbl_deep_extend('force', preset or {}, {
      split = { recursive = true },
      join = { recursive = true },
    })
  )
end

vim.keymap.set('n', '<M-C-K>', tsj.join)
vim.keymap.set('n', '<M-NL>', function()
  vim.opt.operatorfunc = 'v:lua.tsj_split_recursive'
  vim.api.nvim_feedkeys('g@l', 'nx', true)
end)
vim.keymap.set('n', 'g<M-NL>', tsj.split)
