local M = {}

---@class aider_opts_t
M.opts = {
  chat = {
    ---Command to launch aider
    ---@type string[]
    aider_cmd = { 'aider' },
    ---Project root markers to open aider in
    ---@type string[]
    root_markers = require('plugin.aider.utils').fs.root_markers,
    ---Window configuration used to open the aider panel
    ---@type vim.api.keyset.win_config
    win_configs = {
      split = 'right',
      win = 0,
    },
  },
  watch = {
    ---Whether to watch files for inline AI comments
    ---When `true`, launch aider automatically when AI comments are detected
    ---See: https://aider.chat/docs/usage/watch.html#ai-comments
    ---@type boolean
    enabled = true,
    ---Commands to search for AI comments
    ---@type string[][]
    cmds = {
      { 'rg', '-qi', [=[(--|//|#).*\<ai\>[!?]]=], '%s' },
      { 'grep', '-qiE', [=[(--|//|#).*\<ai\>[!?]]=], '%s' },
      {
        vim.v.progpath, -- nvim
        '--clean',
        '--headless',
        [==[+lua
          regex = vim.regex([=[\(--\|//\|#\).*\<ai\>[?!]]=])
          for line in io.lines('%s') do
            if regex:match_str(line) then
              vim.cmd.qa()
            end
          end
          vim.cmd.cq()
        ]==],
        '+qa!', -- ensure that nvim can exit
      },
    },
    ---Interval to check for file or aider buffer update
    ---@type integer
    check_interval = 1000,
    ---Timeout waiting for aider to render
    ---@type integer
    render_timeout = 1600,
  },
}

---@param opts aider_opts_t
---@return boolean success
function M.validate(opts)
  local aider_exe = opts.chat.aider_cmd[1]
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
