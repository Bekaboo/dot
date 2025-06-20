local root_markers = {
  {
    '.goalngci.yml',
    '.golangci.yaml',
    '.golangci.toml',
    '.golangci.json',
  },
  {
    'go.work',
    'go.mod',
  },
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
          -- `--output-format` is removed in golangci-lint v2, see:
          -- https://github.com/golangci/golangci-lint/discussions/5612#discussioncomment-12607774
          lintCommand = 'golangci-lint run --color never --output.tab.path stdout --enable exhaustruct "$(dirname "${INPUT}")"',
          lintFormats = { '%f:%l:%c%*\\s%*\\S%*\\s%m' },
          lintSource = 'golangci-lint',
          lintStdin = false,
          lintSeverity = vim.log.levels.INFO,
          rootMarkers = vim.iter(root_markers):flatten():totable(),
        },
      },
    },
  },
}
