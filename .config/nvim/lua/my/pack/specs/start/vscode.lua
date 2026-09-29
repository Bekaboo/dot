---@type my.pack.spec
return {
  src = 'module://my.plugin.vscode',
  data = {
    enabled = not not vim.g.vscode,
    postload = function()
      require('my.plugin.vscode').setup()
    end,
  },
}
