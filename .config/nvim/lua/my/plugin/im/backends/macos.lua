local base = require('my.plugin.im.backends').base

---macOS input method backend via custom utility `macos-im-switch`, see
---`~/.bin/src/macos_im_switch/`
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
  return vim.fn.has('mac') == 1 and vim.fn.executable('macos-im-switch') == 1
end

---@param buf integer
---@return nil
function backend:try_turn_on(buf)
  if vim.b[buf].im_active and self.cjk_source then
    vim.system({ 'macos-im-switch', 'set', self.cjk_source })
  end
end

---@return nil
function backend:turn_off()
  if self.ascii_source then
    vim.system({ 'macos-im-switch', 'set', self.ascii_source })
  end
end

---@param buf integer
---@return nil
function backend:save_status(buf)
  vim.system({ 'macos-im-switch', 'current' }, {}, function(obj)
    if obj.code ~= 0 then
      return
    end
    local current_source = vim.trim(obj.stdout)
    if current_source ~= self.ascii_source then
      -- IM active
      self.cjk_source = self.cjk_source or current_source
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          vim.b[buf].im_active = true
        end
      end)
    else
      -- IM incactive
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          vim.b[buf].im_active = nil
        end
      end)
    end
  end)
end

return { backend = backend }
