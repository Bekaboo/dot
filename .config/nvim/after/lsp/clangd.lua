---@type lsp_config_t
return {
  filetypes = {
    'c',
    'cpp',
    'objc',
    'objcpp',
    'cuda',
  },
  cmd = { 'clangd' },
  root_markers = {
    {
      '.clangd',
      '.clang-tidy',
      '.clang-format',
    },
    {
      'compile_commands.json',
      'compile_flags.txt',
      'configure.ac',
    },
  },
}
