return setmetatable({}, {
  __index = function(_, key)
    return vim.F.npcall(require, 'plugin.winbar.utils.' .. key)
      or require('utils.' .. key)
  end,
})
