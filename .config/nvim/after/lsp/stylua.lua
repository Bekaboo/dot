local root_markers = { 'stylua.toml', '.stylua.toml' }

return {
  filetypes = { 'lua' },
  cmd = { 'efm-langserver' },
  requires = { 'stylua' },
  name = 'stylua',
  root_markers = root_markers,
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
          formatCommand = 'stylua --stdin-filepath ./"$(cat /dev/urandom | head -c 13)" ${--indent-width:tabSize} ${--range-start:charStart} ${--range-end:charEnd} --color Never -',
          rootMarkers = vim.iter(root_markers):flatten():totable(),
        },
      },
    },
  },
}
