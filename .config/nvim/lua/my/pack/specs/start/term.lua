---@type my.pack.spec
return {
  src = 'module://my.plugin.term',
  data = {
    enabled = not vim.g.vscode,
    events = 'TermOpen',
    postload = function()
      require('my.plugin.term').setup()
    end,
  },
}
