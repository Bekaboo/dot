---@type my.pack.spec
return {
  src = 'module://my.plugin.expandtab',
  data = {
    enabled = not vim.g.vscode,
    events = 'InsertEnter',
    postload = function()
      require('my.plugin.expandtab').setup()
    end,
  },
}
