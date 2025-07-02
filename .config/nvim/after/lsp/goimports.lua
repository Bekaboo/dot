-- Updates your Go import lines, adding missing ones and removing unreferenced
-- ones
--
-- https://pkg.go.dev/golang.org/x/tools/cmd/goimports

local root_markers = { '.goimportsignore', 'go.work', 'go.mod' }

return {
  filetypes = { 'go' },
  cmd = { 'efm-langserver' },
  requires = { 'goimports' },
  name = 'goimports',
  root_markers = root_markers,
  init_options = {
    documentFormatting = true,
  },
  settings = {
    languages = {
      go = {
        {
          formatStdin = true,
          formatCommand = 'goimports',
          rootMarkers = vim.iter(root_markers):flatten():totable(),
        },
      },
    },
  },
}
