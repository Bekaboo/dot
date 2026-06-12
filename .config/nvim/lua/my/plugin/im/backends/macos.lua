local utils = require('my.plugin.im.utils')
local base = require('my.plugin.im.backends').base

---macOS input method backend via macism
---@class my.im.backend.macos: my.im.backend
---@field ascii_source string
---@field cjk_source string?
local backend = {}
backend.__index = backend
setmetatable(backend, base)

---@return my.im.backend.macos
function backend:new()
  local ascii_source = vim.g.im_macos_ascii_source or 'com.apple.keylayout.ABC'
  local cjk_source = vim.g.im_macos_cjk_source
  return setmetatable({
    ascii_source = ascii_source,
    cjk_source = cjk_source,
  }, self)
end

---@return boolean
function backend:detect() -- luacheck: no unused args
  return vim.fn.has('mac') == 1 and vim.fn.executable('macism') == 1
end

---@param buf integer
---@return nil
function backend:on_input_enter(buf)
  if not utils.inside_input_mode() then
    return
  end
  vim.g._im_input_enter = buf
  if vim.b[buf]._im_restore then
    vim.b[buf]._im_restore = nil
    if self.cjk_source then
      vim.system({ 'macism', self.cjk_source })
    end
  end
end

---@param buf integer
---@return nil
function backend:on_input_leave(buf)
  if utils.inside_input_mode() then
    return
  end
  local ascii_source = self.ascii_source
  vim.system({ 'macism' }, {}, function(obj)
    if obj.code ~= 0 then
      vim.system({ 'macism', ascii_source })
      vim.g._im_input_enter = vim.g._im_input_enter or buf
      vim.schedule(function()
        local b = vim.g._im_input_enter
        if vim.api.nvim_buf_is_valid(b) then
          vim.b[b]._im_restore = true
        end
      end)
      return
    end
    local current = vim.trim(obj.stdout)
    if current ~= ascii_source then
      self.cjk_source = self.cjk_source or current
      vim.system({ 'macism', ascii_source })
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
