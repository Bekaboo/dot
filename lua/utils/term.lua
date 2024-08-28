local M = {}

---Compiled vim regex that decides if a command is a TUI app
M.TUI_REGEX = vim.regex(
  [[\v^(sudo(\s+--?(\w|-)+((\s+|\=)\S+)?)*\s+)?]]
    .. [[(/usr/bin/)?]]
    .. [[(n?vim?|vimdiff|emacs(client)?|lem|nano]]
    .. [[|helix|kak|tmux|lazygit|h?top|gdb|fzf|nmtui|sudoedit|ssh|crontab)]]
)

---Check if any of the processes in terminal buffer `buf` is a TUI app
---@param buf integer? buffer handler
---@return boolean?
function M.running_tui(buf)
  local cmds = M.fg_cmds(buf)
  for _, cmd in ipairs(cmds) do
    if M.TUI_REGEX:match_str(cmd) then
      return true
    end
  end
  return false
end

---Get the command running in the foreground in the terminal buffer 'buf'
---@param buf integer? terminal buffer handler, default to 0 (current)
---@return string[]: command running in the foreground
function M.fg_cmds(buf)
  buf = buf or 0
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].bt ~= 'terminal' then
    return {}
  end
  local channel = vim.bo[buf].channel
  local chan_valid, pid = pcall(vim.fn.jobpid, channel)
  if not chan_valid then
    return {}
  end

  local cmds = {}
  for _, stat_cmd_str in
    ipairs(vim.split(vim.fn.system('ps h -o stat,args -g ' .. pid), '\n', {
      trimempty = true,
    }))
  do
    local stat, cmd = unpack(vim.split(stat_cmd_str, '%s+', {
      trimempty = true,
    }))
    if stat:find('^%w+%+') then
      table.insert(cmds, cmd)
    end
  end

  return cmds
end

return M
