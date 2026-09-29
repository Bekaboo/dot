---@type my.pack.spec
return {
  src = 'module://my.plugin.colorcolumn',
  data = {
    enabled = not vim.g.vscode,
    postload = function()
      require('my.plugin.colorcolumn').setup()
    end,
  },
}
