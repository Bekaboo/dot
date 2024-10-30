require('utils.lsp').start({
  cmd = { 'clangd' },
  root_patterns = {
    '.clangd',
    '.clang-tidy',
    '.clang-format',
    'compile_commands.json',
    'compile_flags.txt',
    'configure.ac',
  },
})
