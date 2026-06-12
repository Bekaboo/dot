---Base class for input method backends
---@class my.im.backend
---@field detect fun(self: my.im.backend): boolean
---@field on_input_enter fun(self: my.im.backend, buf: integer)
---@field on_input_leave fun(self: my.im.backend, buf: integer)
local base = {}
base.__index = base

---@class my.im.backends
---@field base my.im.backend
---@field detect fun(): my.im.backend?
local M = {
  base = base,
  fcitx = nil, ---@module 'my.plugin.im.backends.fcitx'
  macos = nil, ---@module 'my.plugin.im.backends.macos'
}

local backends_path = vim.fs.joinpath(
  vim.fn.stdpath('config'),
  'lua/my/plugin/im/backends'
)

---Pick the first available backend and return an instance of it
---@return my.im.backend?
function M.detect()
  for name, type in vim.fs.dir(backends_path) do
    if type == 'file' and vim.endswith(name, '.lua') and name ~= 'init.lua' then
      local module = require('my.plugin.im.backends.' .. name:gsub('%.lua$', ''))
      local instance = module.backend:new()
      if instance:detect() then
        return instance
      end
    end
  end
end

return setmetatable(M, {
  __index = function(_, key)
    return require('my.plugin.im.backends.' .. key)
  end,
})
