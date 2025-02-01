local lsp = require('utils.lsp')

lsp.start({
  cmd = { 'efm-langserver' },
  requires = { 'fish_indent' },
  name = 'efm-formatter-fish_indent',
  init_options = { documentFormatting = true },
  settings = {
    languages = {
      fish = {
        {
          formatCommand = 'fish_indent',
          formatStdin = true,
        },
      },
    },
  },
})

lsp.start({
  cmd = { 'efm-langserver' },
  requires = { 'fish' },
  name = 'efm-linter-fish',
  settings = {
    languages = {
      fish = {
        {
          lintSource = 'fish',
          lintCommand = 'fish --no-execute "${INPUT}"',
          lintFormats = { '%.%#(line %l): %m' },
          lintIgnoreExitCode = true,
        },
      },
    },
  },
})
