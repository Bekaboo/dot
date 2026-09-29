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
function backend:try_turn_on(buf)
  if vim.b[buf].im_active then
    vim.system({ self.cmd, '-o' })
  end
end

---@return nil
function backend:turn_off()
  vim.system({ self.cmd, '-c' })
end

---@param buf integer
---@return nil
function backend:save_status(buf)
  vim.system({ self.cmd }, {}, function(obj)
    if obj.code ~= 0 then
      return
    end
    if tonumber(obj.stdout) == 2 then
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          vim.b[buf].im_active = true
        end
      end)
    else
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          vim.b[buf].im_active = nil
        end
      end)
    end
  end)
end

return { backend = backend }
