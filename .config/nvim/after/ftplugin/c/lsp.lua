local lsp = require('utils.lsp')

local server_configs = {
  {
    cmd = { 'clangd' },
    root_patterns = {
      '.clangd',
      '.clang-tidy',
      '.clang-format',
      'compile_commands.json',
      'compile_flags.txt',
      'configure.ac',
    },
  },
  {
    cmd = { 'ccls' },
    root_patterns = { '.ccls', 'compile_commands.json' },
  },
}

for _, server_config in ipairs(server_configs) do
  if lsp.start(server_config) then
    return
  end
end
