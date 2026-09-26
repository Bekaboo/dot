---@type my.pack.spec
return {
  src = 'module://my.plugin.statuscolumn',
  data = {
    enabled = not vim.g.vscode,
  },
}
