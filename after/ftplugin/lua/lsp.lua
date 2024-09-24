local lsp = require('utils.lsp')

-- Use efm to attach stylua formatter as a language server
local stylua_root_patterns = { 'stylua.toml', '.stylua.toml' }
local efm = vim.fn.executable('stylua') == 1
  and lsp.start({
    cmd = { 'efm-langserver' },
    name = 'efm-formatter-stylua',
    root_patterns = stylua_root_patterns,
    init_options = {
      documentFormatting = true,
      documentRangeFormatting = true,
    },
    settings = {
      languages = {
        lua = {
          {
            formatStdin = true,
            formatCanRange = true,
            formatCommand = 'stylua ${--indent-width:tabSize} ${--range-start:charStart} ${--range-end:charEnd} --color Never -',
            rootMarkers = stylua_root_patterns,
          },
        },
      },
    },
  })

-- Launch lua-language-server, disable its formatting capabilities
-- if efm launched successfully
lsp.start({
  cmd = { 'lua-language-server' },
  root_patterns = { '.luarc.json', '.luarc.jsonc' },
  settings = {
    Lua = {
      hint = { enable = true },
      format = { enable = not efm },
    },
  },
})
