return {
  filetypes = { 'sh' },
  cmd = { 'efm-langserver' },
  requires = { 'shfmt' },
  name = 'shfmt',
  init_options = { documentFormatting = true },
  settings = {
    languages = {
      sh = {
        {
          formatCommand = 'shfmt --filename ${INPUT} -',
          formatStdin = true,
        },
      },
    },
  },
}
