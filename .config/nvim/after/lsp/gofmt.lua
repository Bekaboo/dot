local root_markers = { 'go.work', 'go.mod' }

return {
  filetypes = { 'go' },
  cmd = { 'efm-langserver' },
  requires = { 'gofmt' },
  name = 'gofmt',
  root_markers = root_markers,
  init_options = {
    documentFormatting = true,
  },
  settings = {
    languages = {
      go = {
        {
          formatStdin = true,
          formatCommand = 'gofmt -s',
          rootMarkers = vim.iter(root_markers):flatten():totable(),
        },
      },
    },
  },
}
