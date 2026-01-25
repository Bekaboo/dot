---@class my.winbar.source
---@field get_symbols fun(buf: integer, win: integer, cursor: integer[]): my.winbar.symbol[]

---@type table<string, my.winbar.source>
return setmetatable({}, {
  __index = function(_, key)
    return require('my.plugin.winbar.sources.' .. key)
  end,
})
