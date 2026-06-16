local base = require('my.plugin.im.backends').base

---Windows input method backend via im-select
---@class my.im.backend.windows: my.im.backend
---@field english_locale string
---@field cjk_locale string?
local backend = {}
backend.__index = backend
setmetatable(backend, base)

---@return my.im.backend.windows
function backend:new()
  local english_locale = vim.g.im_windows_english_locale or '1033'
  local cjk_locale = vim.g.im_windows_cjk_locale
  return setmetatable(
    { english_locale = english_locale, cjk_locale = cjk_locale },
    self
  )
end

---@return boolean
function backend:detect() -- luacheck: no unused args
  return vim.fn.has('win32') == 1 and vim.fn.executable('im-select') == 1
end

---@param buf integer
---@return nil
function backend:on_input_enter(buf)
  vim.g._im_input_enter = buf
  if vim.b[buf]._im_restore then
    vim.b[buf]._im_restore = nil
    if self.cjk_locale then
      vim.system({ 'im-select', self.cjk_locale })
    end
  end
end

---@param buf integer
---@return nil
function backend:on_input_leave(buf)
  vim.system({ 'im-select' }, {}, function(obj)
    if obj.code ~= 0 then
      vim.system({ 'im-select', self.english_locale })
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
    if current ~= self.english_locale then
      self.cjk_locale = self.cjk_locale or current
      vim.system({ 'im-select', self.english_locale })
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
