local M = {}

local is_windows ---@type boolean?

---Check if nvim is running on Windows
---@return boolean
function M.is_windows()
  if is_windows ~= nil then
    return is_windows
  end
  is_windows = vim.uv.os_uname().sysname:find('Windows', 1, true) ~= nil
  return is_windows
end

---Use GNU tools shipped with git on Windows
---@type table<string, string|false>
M.gnu_tool_paths = vim.defaulttable(function(cmd)
  if not M.is_windows() then
    return cmd
  end
  local git = vim.fn.exepath('git')
  if git == '' then
    return false
  end
  return vim.fs.joinpath(
    vim.fs.joinpath(vim.fs.dirname(vim.fs.dirname(git)), 'usr/bin'),
    cmd
  )
end)

return M
