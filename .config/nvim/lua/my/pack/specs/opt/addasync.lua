---@type my.pack.spec
return {
  src = 'module://my.plugin.addasync',
  data = {
    enabled = not vim.g.vscode,
    events = 'InsertEnter',
    postload = function()
      require('my.plugin.addasync').setup()
    end,
  },
}
