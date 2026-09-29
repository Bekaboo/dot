---@type my.pack.spec
return {
  src = 'module://my.plugin.jupytext',
  data = {
    enabled = not vim.g.vscode,
    events = { event = 'BufReadCmd', pattern = '*.ipynb' },
    postload = function()
      require('my.plugin.jupytext').setup()
    end,
  },
}
