return {
  filetypes = {
    'typescript',
    'javascript',
  },
  cmd = {
    'typescript-language-server',
    '--stdio',
  },
  root_markers = {
    {
      'tsconfig.json',
      'jsconfig.json',
    },
    { 'package.json' },
  },
  init_options = {
    hostInfo = 'neovim',
  },
}
