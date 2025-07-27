---@type lsp_config_t
return {
  filetypes = { 'fish' },
  cmd = { 'efm-langserver' },
  requires = { 'fish_indent' },
  name = 'fish_indent',
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
}
