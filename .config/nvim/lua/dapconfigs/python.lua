local M = {}
local dap_utils = require('utils.dap')

---@type dapcache_t
local cache = dap_utils.new_cache()

M.adapter = function(cb, config)
  if config.request == 'attach' then
    local port = (config.connect or config).port
    local host = (config.connect or config).host or '127.0.0.1'
    cb({
      type = 'server',
      port = assert(
        port,
        '`connect.port` is required for a python `attach` configuration'
      ),
      host = host,
      options = {
        source_filetype = 'python',
      },
    })
  else
    cb({
      type = 'executable',
      command = 'python3',
      args = { '-m', 'debugpy.adapter' },
      options = {
        source_filetype = 'python',
      },
    })
  end
end

M.config = {
  {
    type = 'python',
    request = 'launch',
    name = 'Launch file',
    program = '${file}',
    args = dap_utils.get_args(cache),
    pythonPath = function()
      return vim.fn.exepath('python3')
    end,
    -- Fix debugpy cannot find local python modules, assuming cwd has been
    -- set to project root, see https://stackoverflow.com/a/63271966
    env = function()
      return { PYTHONPATH = vim.fn.getcwd(0) }
    end,
  },
}

return M
