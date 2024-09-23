local M = {}

M.adapter = function(callback, config)
  if config.mode == 'remote' and config.request == 'attach' then
    callback({
      type = 'server',
      host = config.host or '127.0.0.1',
      port = config.port or '38697',
    })
  else
    callback({
      type = 'server',
      port = '${port}',
      executable = {
        command = 'dlv',
        args = {
          'dap',
          '-l',
          '127.0.0.1:${port}',
          '--log',
          '--log-output=dap',
        },
        detached = vim.fn.has('win32') == 0,
      },
    })
  end
end

-- https://github.com/go-delve/delve/blob/master/Documentation/usage/dlv_dap.md
M.config = {
  {
    type = 'delve',
    name = 'Debug',
    request = 'launch',
    program = '${file}',
  },
  -- Configuration for debugging test files
  {
    type = 'delve',
    name = 'Debug test',
    request = 'launch',
    mode = 'test',
    program = '${file}',
  },
  -- Works with go.mod packages and sub packages
  {
    type = 'delve',
    name = 'Debug test (go.mod)',
    request = 'launch',
    mode = 'test',
    program = './${relativeFileDirname}',
  },
}

return M
