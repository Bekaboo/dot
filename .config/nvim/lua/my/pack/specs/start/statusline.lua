---@type my.pack.spec
return {
  src = 'module://my.plugin.statusline',
  data = {
    enabled = not vim.g.vscode,
  },
}
