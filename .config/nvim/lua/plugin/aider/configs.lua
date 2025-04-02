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

---@param opts aider_opts_t
---@return boolean success
function M.validate(opts)
  local aider_exe = opts.aider_cmd[1]
  if not aider_exe or vim.fn.executable(aider_exe) == 0 then
    vim.notify_once(
      string.format('[aider] `%s` is not executable', tostring(aider_exe)),
      vim.log.levels.WARN
    )
    return false
  end
  return true
end

---Merge user-provided opts with default opts
---@param opts aider_opts_t?
---@return boolean success
function M.set(opts)
  local new_opts = vim.tbl_deep_extend('force', M.opts, opts or {})
  if M.validate(new_opts) then
    M.opts = new_opts
    return true
  end
  return false
end

return M
