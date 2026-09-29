---@type my.pack.spec
return {
  src = 'module://my.plugin.readline',
  data = {
    enabled = not vim.g.vscode,
    events = { 'CmdlineEnter', 'InsertEnter' },
    postload = function()
      require('my.plugin.readline').setup()
    end,
  },
}
