local lsp = require('utils.lsp')

if vim.fn.executable('fish_indent') == 1 then
  lsp.start({
    cmd = { 'efm-langserver' },
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
end

if vim.fn.executable('fish') == 1 then
  lsp.start({
    cmd = { 'efm-langserver' },
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
end
