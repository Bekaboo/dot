local root_markers = {
  '.goalngci.yml',
  '.golangci.yaml',
  '.golangci.toml',
  '.golangci.json',
  'go.work',
  'go.mod',
}

return {
  filetypes = { 'go' },
  cmd = { 'efm-langserver' },
  requires = { 'golangci-lint' },
  name = 'golangci-lint',
  root_markers = root_markers,
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
          rootMarkers = root_markers,
        },
      },
    },
  },
}
