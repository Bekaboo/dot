return setmetatable({
  bar = nil, ---@module 'my.plugin.winbar.utils.bar'
  menu = nil, ---@module 'my.plugin.winbar.utils.menu'
  source = nil, ---@module 'my.plugin.winbar.utils.source'
}, {
  __index = function(_, key)
    return vim.F.npcall(require, 'my.plugin.winbar.utils.' .. key)
      or require('my.utils.' .. key)
  end,
})
