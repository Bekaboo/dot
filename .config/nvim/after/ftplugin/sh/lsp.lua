local lsp = require('utils.lsp')

local efm = lsp.start({
  cmd = { 'efm-langserver' },
  requires = { 'shfmt' },
  name = 'efm-formatter-shfmt',
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
})

lsp.start({
  cmd = { 'bash-language-server', 'start' },
  on_attach = efm and function(client)
    client.server_capabilities.documentFormattingProvider = false
  end or nil,
  settings = {
    bashIde = {
      globPattern = vim.env.GLOB_PATTERN or '*@(.sh|.inc|.bash|.command)',
    },
  },
})
