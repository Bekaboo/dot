---@type my.pack.spec
return {
  src = 'module://my.plugin.intro',
  data = {
    enabled = not vim.g.vscode,
  },
}
