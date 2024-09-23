local M = {}

---@type dapcache_t
local cache = { args = {} }

M.adapter = {
  name = 'bashdb',
  type = 'executable',
  command = 'node',
  args = {
    vim.fn.stdpath('data') .. '/vscode-bash-debug/extension/out/bashDebug.js',
  },
}

local datapath = vim.fn.stdpath('data') --[[@as string]]

M.config = {
  {
    type = 'bashdb',
    request = 'launch',
    name = 'Launch file',
    showDebugOutput = true,
    pathBashdb = vim.fs.joinpath(
      datapath,
      'vscode-bash-debug/extension/bashdb_dir/bashdb'
    ),
    pathBashdbLib = vim.fs.joinpath(
      datapath,
      '/vscode-bash-debug/extension/bashdb_dir/'
    ),
    trace = true,
    file = '${file}',
    program = '${file}',
    cwd = '${workspaceFolder}',
    pathCat = 'cat',
    pathBash = '/bin/bash',
    pathMkfifo = 'mkfifo',
    pathPkill = 'pkill',
    env = {},
    terminalKind = 'integrated',
    args = function()
      local args = ''
      local fname = vim.fn.expand('%:t')
      vim.ui.input({
        prompt = 'Enter arguments: ',
        default = cache.args[fname],
        completion = 'file',
      }, function(input)
        args = input
        cache.args[fname] = args
        vim.cmd.stopinsert()
      end)
      return vim.split(args, ' ')
    end,
  },
}

return M
