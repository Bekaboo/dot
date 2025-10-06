-- LSP wrapper for typescript extension of vscode
-- https://github.com/yioneko/vtsls

---@type lsp.config
return {
  filetypes = {
    'typescript',
    'javascript',
    'typescriptreact',
    'javascriptreact',
  },
  cmd = { 'vtsls', '--stdio' },
  root_markers = {
    {
      'tsconfig.json',
      'jsconfig.json',
    },
    { 'package.json' },
  },
  init_options = {
    hostInfo = 'neovim',
  },
}
