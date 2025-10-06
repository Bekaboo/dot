---@type lsp.config
return {
  filetypes = { 'go' },
  cmd = { 'efm-langserver' },
  requires = { 'golangci-lint', 'dirname' },
  name = 'golangci-lint',
  root_markers = {
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
  },
  settings = {
    languages = {
      go = {
        {
          -- Must run on the package dir to lint all files, else the linter
          -- will fail to find definitions in other files in the same package
          -- `--output-format` is removed in golangci-lint v2, see:
          -- https://github.com/golangci/golangci-lint/discussions/5612#discussioncomment-12607774
          lintCommand = 'golangci-lint run --color never --show-stats=false --output.text.path stdout --output.text.print-issued-lines=false "$(dirname "${INPUT}")"',
          lintFormats = { '%f:%l:%c: %m' },
          lintSource = 'golangci-lint',
          lintAfterOpen = true,
          lintStdin = false,
          lintSeverity = 3,
        },
      },
    },
  },
}
