-- Updates your Go import lines, adding missing ones and removing unreferenced
-- ones
--
-- https://pkg.go.dev/golang.org/x/tools/cmd/goimports

---@type lsp_config_t
return {
  filetypes = { 'go' },
  cmd = { 'efm-langserver' },
  requires = { 'goimports' },
  name = 'goimports',
  root_markers = { '.goimportsignore', 'go.work', 'go.mod' },
  init_options = {
    documentFormatting = true,
  },
  settings = {
    languages = {
      go = {
        {
          formatStdin = true,
          formatCommand = 'goimports',
        },
      },
    },
  },
}
