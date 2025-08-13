---@type lsp_config_t
return {
  filetypes = { 'go' },
  cmd = { 'efm-langserver' },
  requires = { 'gofmt' },
  name = 'gofmt',
  root_markers = { 'go.work', 'go.mod' },
  init_options = {
    documentFormatting = true,
  },
  settings = {
    languages = {
      go = {
        {
          formatStdin = true,
          formatCommand = 'gofmt -s',
        },
      },
    },
  },
}
