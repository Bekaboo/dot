local lsp = require('utils.lsp')

lsp.start({
  cmd = { 'efm-langserver' },
  requires = { 'luacheck' },
  name = 'efm-linter-luacheck',
  root_markers = { '.luacheckrc' },
  settings = {
    languages = {
      lua = {
        {
          lintSource = 'luacheck',
          lintCommand = 'luacheck --codes --no-color --quiet -',
          lintFormats = { '%.%#:%l:%c: (%t%n) %m' },
          lintStdin = true,
          lintIgnoreExitCode = true,
          rootMarkers = { '.luacheckrc' },
        },
      },
    },
  },
})

-- Use efm to attach stylua formatter as a language server
local stylua_root_markers = { 'stylua.toml', '.stylua.toml' }
local formatter = lsp.start({
  cmd = { 'efm-langserver' },
  requires = { 'stylua' },
  name = 'efm-formatter-stylua',
  root_markers = stylua_root_markers,
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
          -- Use `--stdin-filepath` as a workaround to make stylua respect
          -- `.stylua.toml`, see https://github.com/JohnnyMorganz/StyLua/issues/928
          formatCommand = 'stylua --stdin-filepath ./"$(tr -dc A-Za-z0-9 </dev/urandom | head -c 13)" ${--indent-width:tabSize} ${--range-start:charStart} ${--range-end:charEnd} --color Never -',
          rootMarkers = stylua_root_markers,
        },
      },
    },
  },
})

-- Launch lua-language-server, disable its formatting capabilities
-- if efm launched successfully
lsp.start({
  cmd = { 'lua-language-server' },
  root_markers = { '.luarc.json', '.luarc.jsonc' },
  settings = {
    Lua = {
      hint = { enable = true },
      format = { enable = not formatter },
    },
  },
})
