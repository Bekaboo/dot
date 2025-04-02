local M = {}

---@class aider_opts_t
M.opts = {
  aider_cmd = { 'aider' },
  ---@type vim.api.keyset.win_config
  win_configs = {
    split = 'right',
    win = 0,
  },
}

---Merge user-provided opts with default opts
---@param opts aider_opts_t?
---@return boolean success
function M.set(opts)
  M.opts = vim.tbl_deep_extend('force', M.opts, opts or {})

  local aider_exe = M.opts.aider_cmd[1]
  if not aider_exe or vim.fn.executable(aider_exe) == 0 then
    vim.notify_once(
      string.format(
        '[aider] aider command `%s` is not executable',
        tostring(aider_exe)
      )
    )
    return false
  end

  return true
end

return M
