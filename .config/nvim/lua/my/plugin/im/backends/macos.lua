local configs = require('my.plugin.im.configs')
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
function backend:on_input_enter(buf)
  if not configs.opts.inside_input_mode() then
    return
  end
  vim.g._im_input_enter = buf
  if vim.b[buf]._im_restore then
    vim.b[buf]._im_restore = nil
    if self.cjk_source then
      vim.system({ 'macos-im-switch', 'set', self.cjk_source })
    end
  end
end

---@param buf integer
---@return nil
function backend:on_input_leave(buf)
  if configs.opts.inside_input_mode() then
    return
  end
  vim.system({ 'macos-im-switch', 'current' }, {}, function(obj)
    -- Failed to get current input method, switch to ASCII source anyway
    if obj.code ~= 0 then
      vim.system({ 'macos-im-switch', 'set', self.ascii_source })
      vim.g._im_input_enter = vim.g._im_input_enter or buf
      vim.schedule(function()
        local b = vim.g._im_input_enter
        if vim.api.nvim_buf_is_valid(b) then
          vim.b[b]._im_restore = true
        end
      end)
      return
    end
    -- Successfully get current input method, skip if current is already ASCII
    -- source to avoid showing IM switch indicator
    local current = vim.trim(obj.stdout)
    if current ~= self.ascii_source then
      self.cjk_source = self.cjk_source or current
      vim.system({ 'macos-im-switch', 'set', self.ascii_source })
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
