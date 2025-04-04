local M = {}

---@class aider_opts_t
M.opts = {
  ---Project root markers to open aider in
  ---@type string[]
  root_markers = require('plugin.aider.utils').fs.root_markers,
  ---@type aider_chat_opts_t
  chat = {
    ---Command to launch aider
    ---@type string[]
    cmd = { 'aider' },
    ---Window configuration used to open the aider panel
    ---@type vim.api.keyset.win_config
    win_configs = {
      split = 'right',
      win = 0,
    },
    ---Time interval (in ms) to check aider buffer updates
    ---Not recommended to change
    ---@type integer
    check_interval = 500,
    ---Timeout (in ms) waiting for aider's ai comment watcher to be ready after
    ---rendering input prompt ">"
    ---Not recommended to change
    ---@type integer
    watcher_timeout = 500,
  },
  watch = {
    ---Whether to watch files for inline AI comments
    ---When `true`, launch aider automatically when AI comments are detected
    ---See: https://aider.chat/docs/usage/watch.html#ai-comments
    ---@type boolean
    enabled = true,
    ---Commands to search for AI comments
    ---See: https://aider.chat/docs/usage/watch.html#comment-styles
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
  },
}

---Merge user-provided opts with default opts
---@param opts aider_opts_t?
function M.set(opts)
  M.opts = vim.tbl_deep_extend('force', M.opts, opts or {})
end

return M
