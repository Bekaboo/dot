return {
  filetypes = { 'lua' },
  cmd = { 'efm-langserver' },
  requires = { 'luacheck' },
  name = 'luacheck',
  root_markers = { '.luacheckrc' },
  settings = {
    languages = {
      lua = {
        {
          lintSource = 'luacheck',
          lintCommand = 'luacheck --codes --no-color --quiet -',
          lintFormats = { '%.%#:%l:%c: (%t%n) %m' },
          lintAfterOpen = true,
          lintStdin = true,
          lintIgnoreExitCode = true,
          rootMarkers = { '.luacheckrc' },
        },
      },
    },
  },
}
