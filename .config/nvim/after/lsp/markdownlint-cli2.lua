---@type my.lsp.config
return {
  filetypes = { 'markdown' },
  cmd = { 'efm-langserver' },
  requires = { 'markdownlint-cli2' },
  name = 'markdownlint-cli2',
  init_options = {
    documentFormatting = true,
  },
  settings = {
    languages = {
      markdown = {
        {
          formatCommand = 'markdownlint-cli2 --format',
          formatStdin = true,
        },
        {
          lintSource = 'markdownlint-cli2',
          lintCommand = 'markdownlint-cli2 -',
          lintFormats = {
            '%f:%l %trror %m',
            '%f:%l %tarning %m',
          },
          lintAfterOpen = true,
          lintStdin = true,
          lintIgnoreExitCode = true,
        },
      },
    },
  },
}
