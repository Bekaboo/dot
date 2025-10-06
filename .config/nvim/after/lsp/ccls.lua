---@type lsp.config
return {
  filetypes = {
    'c',
    'cpp',
    'objc',
    'objcpp',
    'cuda',
  },
  cmd = { 'ccls' },
  root_markers = {
    { '.ccls' },
    { 'compile_commands.json' },
  },
}
