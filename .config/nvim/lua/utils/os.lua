local M = {}

---Normalize executable path
---If `cmd` is executable, it is returned as is; else we try to find it under
---git installation and return its path; return `false` if we cannot find it
---@type table<string, string|false>
M.exepath = vim.defaulttable(function(cmd)
  if vim.fn.executable(cmd) == 1 then
    return cmd
  end

  -- Windows git intallation ships some GNU tools, so try to find tools under
  -- git installation
  local git = vim.fn.exepath('git')
  if git == '' then
    return false
  end

  cmd = vim.fs.joinpath(
    vim.fs.joinpath(vim.fs.dirname(vim.fs.dirname(git)), 'usr/bin'),
    cmd
  )
  return vim.fn.executable(cmd) == 1 and cmd or false
end)

return M
