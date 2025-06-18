local M = {}
local utils = require('utils')

---@class aider_opts_t
M.opts = {
  ---Project root markers to open aider in
  ---@param path string
  ---@return string?
  root = function(path)
    ---@param dir string?
    ---@return string?
    local function validate(dir)
      return dir
          and vim.fn.isdirectory(dir) == 1
          -- Aider will freeze if opened in home dir
          and not utils.fs.is_home_dir(dir)
          and not utils.fs.is_root_dir(dir)
          and dir
        or nil
    end
    return validate(require('utils.fs').root(path, '.git'))
      or validate(require('utils.fs').root(path))
      or vim.fn.isdirectory(path) == 1 and path
      or vim.fs.dirname(path)
  end,
  ---@type aider_chat_opts_t
  chat = {
    ---Command to launch aider
    ---@param path string
    ---@return string[]
    cmd = function(path)
      local aider_cmd = { 'aider' }
      if not utils.fs.root(path, '.git') then
        table.insert(aider_cmd, '--no-git')
      end
      return aider_cmd
    end,
    ---Window configuration used to open the aider panel
    ---@see vim.api.nvim_open_win
    win_configs = {
      win = 0,
      split = function()
        return vim.api.nvim_win_get_width(0)
              > 3 * vim.api.nvim_win_get_height(0)
            and 'right'
          or 'below'
      end,
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
      { 'rg', '-qi', [=[(--|//|#|;).*\<ai\>[!?]]=], '%s' },
      { 'grep', '-qiE', [=[(--|//|#|;).*\<ai\>[!?]]=], '%s' },
      {
        vim.v.progpath, -- nvim
        '--clean',
        '--headless',
        [==[+lua
          regex = vim.regex([=[\(--\|//\|#\|;\).*\<ai\>[?!]]=])
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

  -- Ensure aider's file watcher is enabled if `watch` is enabled in this
  -- plugin, insert `--watch-files` as the first flag to respect potential
  -- `--no-watch-files` flag in cmd
  if M.opts.watch.enabled then
    M.opts.chat.cmd = (function(cb)
      return function(path)
        local aider_cmd = cb(path)
        table.insert(aider_cmd, 2, '--watch-files')
        return aider_cmd
      end
    end)(M.opts.chat.cmd)
  end
end

return M
