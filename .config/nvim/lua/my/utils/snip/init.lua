---@diagnostic disable: assign-type-mismatch

return setmetatable({
  conds = nil, ---@module 'my.utils.snip.conds'
  funcs = nil, ---@module 'my.utils.snip.funcs'
  nodes = nil, ---@module 'my.utils.snip.nodes'
  snips = nil, ---@module 'my.utils.snip.snips'
}, {
  __index = function(_, key)
    return require('my.utils.snip.' .. key)
  end,
})
