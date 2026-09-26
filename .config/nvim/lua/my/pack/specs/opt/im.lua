---@type my.pack.spec
return {
  src = 'module://my.plugin.im',
  data = {
    enabled = not vim.g.vscode,
    events = {
      event = 'ModeChanged',
      pattern = '*:[ictRss\x13]*',
    },
    postload = function()
      require('my.plugin.im').setup()
    end,
  },
}
