local M = {}

---@class my.im.config.opts
M.opts = {
  ---List of backend instances to try, or a function returning such a list.
  ---The first backend whose `detect()` returns true will be used.
  ---Defaults to auto-discovering backends from the backends directory.
  ---@type my.im.backend[]|fun(): my.im.backend[]
  backends = function()
    local backends_path =
      vim.fs.joinpath(vim.fn.stdpath('config'), 'lua/my/plugin/im/backends')
    local backends = {}
    for name, type in vim.fs.dir(backends_path) do
      if
        type == 'file'
        and vim.endswith(name, '.lua')
        and name ~= 'init.lua'
      then
        local module =
          require('my.plugin.im.backends.' .. name:gsub('%.lua$', ''))
        table.insert(backends, module.backend:new())
      end
    end
    return backends
  end,
  ---Check if we are in *input modes*.
  ---
  ---*Input modes* are modes where the input method should be activated.
  ---Default includes insert mode, replace mode, terminal mode, select mode,
  ---and command mode when command type is '/', '?', '@', or '-'.
  ---
  ---Notice that command mode when command type is ':', '>', or '=' is not
  ---considered as input modes, because in these cases one will not want to
  ---insert CJK, even if the input method is activated in the current buffer.
  ---@type fun(): boolean
  inside_input_mode = function()
    local mode = vim.fn.mode()
    if
      mode:find('^[itRss\x13]')
      or mode:find('^c') and vim.fn.getcmdtype():find('[/?@-]')
    then
      return true
    end
    return false
  end,
}

---Set im options
---@param new_opts my.im.config.opts?
function M.set(new_opts)
  M.opts = vim.tbl_deep_extend('force', M.opts, new_opts or {})
end

---Evaluate a dynamic option value (with type T|fun(...): T)
---@generic T
---@param opt T|fun(...): T
---@return T
function M.eval(opt, ...)
  if opt and vim.is_callable(opt) then
    return opt(...)
  end
  return opt
end

return M
