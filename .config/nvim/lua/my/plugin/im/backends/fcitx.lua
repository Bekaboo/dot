local base = require('my.plugin.im.backends').base

---fcitx5 / fcitx input method backend
---@class my.im.backend.fcitx: my.im.backend
---@field cmd string
local backend = {}
backend.__index = backend
setmetatable(backend, base)

---@return my.im.backend.fcitx
function backend:new()
  local cmd = nil ---@type string?
  for _, c in ipairs({ 'fcitx5-remote', 'fcitx-remote' }) do
    if vim.fn.executable(c) == 1 then
      cmd = c
    end
  end
  return setmetatable({ cmd = cmd }, self)
end

---@return boolean
function backend:detect()
  return self.cmd ~= nil
end

---@param buf integer
---@return nil
function backend:on_input_enter(buf)
  vim.g._im_input_enter = buf
  if vim.b[buf]._im_restore then
    vim.b[buf]._im_restore = nil
    vim.system({ self.cmd, '-o' })
  end
end

---@param buf integer
---@return nil
function backend:on_input_leave(buf)
  vim.system({ self.cmd }, {}, function(obj)
    if obj.code ~= 0 or tonumber(obj.stdout) == 2 then
      vim.system({ self.cmd, '-c' })
      vim.g._im_input_enter = vim.g._im_input_enter or buf
      vim.schedule(function()
        local b = vim.g._im_input_enter
        if vim.api.nvim_buf_is_valid(b) then
          vim.b[b]._im_restore = true
        end
      end)
    end
  end)
end

return { backend = backend }
