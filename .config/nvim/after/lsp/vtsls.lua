-- LSP wrapper for typescript extension of vscode
-- https://github.com/yioneko/vtsls

---@type lsp_config_t
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
