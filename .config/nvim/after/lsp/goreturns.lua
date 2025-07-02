-- Adds zero-value return values to incomplete Go return statements, also
-- organizes imports & formats code, inspired by and based on goimports
--
-- https://pkg.go.dev/github.com/sqs/goreturns

local root_markers = { 'go.work', 'go.mod' }

return {
  filetypes = { 'go' },
  cmd = { 'efm-langserver' },
  requires = { 'goreturns' },
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
          formatCommand = 'goreturns',
          rootMarkers = vim.iter(root_markers):flatten():totable(),
        },
      },
    },
  },
}
