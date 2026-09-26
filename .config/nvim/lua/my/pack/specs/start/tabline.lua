---@type my.pack.spec
return {
  src = 'module://my.plugin.tabline',
  data = {
    enabled = not vim.g.vscode,
  },
}
