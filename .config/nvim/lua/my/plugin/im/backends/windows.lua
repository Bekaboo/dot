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
function backend:try_turn_on(buf)
  if vim.b[buf].im_active and self.cjk_locale then
    vim.system({ 'im-select', self.cjk_locale })
  end
end

---@return nil
function backend:turn_off()
  if self.english_locale then
    vim.system({ 'im-select', self.english_locale })
  end
end

---@param buf integer
---@return nil
function backend:save_status(buf)
  vim.system({ 'im-select' }, {}, function(obj)
    if obj.code ~= 0 then
      return
    end
    local current_locale = vim.trim(obj.stdout)
    if current_locale ~= self.english_locale then
      self.cjk_locale = self.cjk_locale or current_locale
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
