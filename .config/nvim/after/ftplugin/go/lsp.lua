local lsp = require('utils.lsp')

local root_markers = { 'go.work', 'go.mod' }

local golangci_root_markers = vim.list_extend({
  '.goalngci.yml',
  '.golangci.yaml',
  '.golangci.toml',
  '.golangci.json',
}, root_markers)

lsp.start({
  cmd = { 'efm-langserver' },
  requires = { 'golangci-lint' },
  name = 'efm-linter-golangci-lint',
  root_markers = golangci_root_markers,
  settings = {
    languages = {
      go = {
        {
          -- Must run on the package dir to lint all files, else the linter
          -- will fail to find definitions in other files in the same package
          lintCommand = 'golangci-lint run --color never --out-format tab --enable exhaustruct "$(dirname "${INPUT}")"',
          lintFormats = { '%f:%l:%c%*\\s%*\\S%*\\s%m' },
          lintSource = 'golangci-lint',
          lintStdin = false,
          lintSeverity = 2,
          rootMarkers = golangci_root_markers,
        },
      },
    },
  },
})

local formatter = lsp.start({
  cmd = { 'efm-langserver' },
  requires = { 'gofmt' },
  name = 'efm-formatter-gofmt',
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
          rootMarkers = root_markers,
        },
      },
    },
  },
})

-- Suppress error 'SWIG + Go: C source files not allowed when not using cgo'
-- https://stackoverflow.com/questions/30248259/swig-go-c-source-files-not-allowed-when-not-using-cgo
vim.env.CGO_ENABLED = 0

lsp.start({
  cmd = { 'gopls' },
  root_markers = root_markers,
  on_attach = formatter and function(client)
    client.server_capabilities.documentFormattingProvider = false
  end or nil,
  settings = {
    gopls = {
      completeUnimported = true,
      usePlaceholders = true,
      analyses = {
        unusedparams = true,
        shadow = true,
      },
      staticcheck = true,
      hints = {
        assignVariableTypes = true,
        compositeLiteralFields = true,
        constantValues = true,
        functionTypeParameters = true,
        parameterNames = true,
        rangeVariableTypes = true,
      },
    },
  },
})
