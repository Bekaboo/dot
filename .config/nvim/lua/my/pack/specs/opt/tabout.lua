---@type my.pack.spec
return {
  src = 'module://my.plugin.tabout',
  data = {
    enabled = not vim.g.vscode,
    events = 'InsertEnter',
    postload = function()
      require('my.plugin.tabout').setup()
    end,
  },
}
