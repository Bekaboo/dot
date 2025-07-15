-- Adds zero-value return values to incomplete Go return statements, also
-- organizes imports & formats code, inspired by and based on goimports
--
-- https://pkg.go.dev/github.com/sqs/goreturns

return {
  filetypes = { 'go' },
  cmd = { 'efm-langserver' },
  requires = { 'goreturns' },
  name = 'goimports',
  root_markers = { 'go.work', 'go.mod' },
  init_options = {
    documentFormatting = true,
  },
  settings = {
    languages = {
      go = {
        {
          formatStdin = true,
          formatCommand = 'goreturns',
        },
      },
    },
  },
}
