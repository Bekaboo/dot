return setmetatable({}, {
  __index = function(_, key)
    return vim.F.npcall(require, 'plugin.aider.utils.' .. key)
      or require('utils.' .. key)
  end,
})
