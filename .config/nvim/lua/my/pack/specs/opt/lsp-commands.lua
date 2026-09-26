---@type my.pack.spec
return {
  src = 'module://my.plugin.lsp-commands',
  data = {
    enabled = not vim.g.vscode,
    events = { 'Syntax', 'FileType', 'LspAttach', 'DiagnosticChanged' },
    postload = function()
      require('my.plugin.lsp-commands').setup()
    end,
  },
}
