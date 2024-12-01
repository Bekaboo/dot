local lsp = require('utils.lsp')

if vim.fn.executable('luacheck') == 1 then
  lsp.start({
    cmd = { 'efm-langserver' },
    name = 'efm-linter-luacheck',
    root_patterns = { '.luacheckrc' },
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
end

-- Use efm to attach stylua formatter as a language server
local stylua_root_patterns = { 'stylua.toml', '.stylua.toml' }
local formatter = vim.fn.executable('stylua') == 1
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
            -- Use `--stdin-filepath` as a workaround to make stylua respect
            -- `.stylua.toml`, see https://github.com/JohnnyMorganz/StyLua/issues/928
            formatCommand = 'stylua --stdin-filepath ./"$(tr -dc A-Za-z0-9 </dev/urandom | head -c 13)" ${--indent-width:tabSize} ${--range-start:charStart} ${--range-end:charEnd} --color Never -',
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
      format = { enable = not formatter },
    },
  },
})
