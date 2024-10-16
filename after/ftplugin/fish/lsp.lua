if vim.fn.executable('fish_indent') == 1 then
  require('utils.lsp').start({
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
