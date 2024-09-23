local M = {}

---@type dapcache_t
local cache = { args = {} }

M.adapter = {
  type = 'server',
  port = '${port}',
  executable = {
    command = vim.fn.exepath('codelldb'), -- must be full path
    args = { '--port', '${port}' },
  },
}

M.config = {
  {
    type = 'codelldb',
    name = 'Launch file',
    request = 'launch',
    cwd = '${workspaceFolder}',
    stopOnEntry = false,
    program = function()
      local program
      vim.ui.input({
        prompt = 'Enter path to executable: ',
        default = vim.fs.find({ vim.fn.expand('%:t:r'), 'a.out' }, {
          path = vim.fn.expand('%:p:h'),
          upward = true,
        })[1] or cache.program,
        completion = 'file',
      }, function(input)
        program = input
        cache.program = program
        vim.cmd.stopinsert()
      end)
      return vim.fn.fnamemodify(program, ':p')
    end,

    args = function()
      local args = ''
      local fpath_base = vim.fn.expand('%:p:r')
      vim.ui.input({
        prompt = 'Enter arguments: ',
        default = cache.program and cache.args[cache.program]
          or cache.args[fpath_base],
        completion = 'file',
      }, function(input)
        args = input
        cache.args[cache.program or fpath_base] = args
        vim.cmd.stopinsert()
      end)
      return vim.split(args, ' ')
    end,
  },
}

return M
