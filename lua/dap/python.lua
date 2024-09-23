local M = {}

---@type dapcache_t
local cache = { args = {} }

M.adapter = {
  type = 'executable',
  command = 'python',
  args = { '-m', 'debugpy.adapter' },
}

M.config = {
  {
    type = 'python',
    request = 'launch',
    name = 'Launch file',
    program = '${file}',
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

    pythonPath = function()
      local venv = vim.fs.find({ 'venv', '.venv' }, {
        path = vim.fn.expand('%:p:h'),
        upward = true,
      })[1]
      if venv and vim.fn.executable(venv .. '/bin/python') == 1 then
        return venv .. '/bin/python'
      end
      return vim.fn.exepath('python')
    end,
  },
}

return M
