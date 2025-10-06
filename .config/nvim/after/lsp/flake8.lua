---@type lsp.config
return {
  filetypes = { 'python' },
  cmd = { 'efm-langserver' },
  requires = { 'flake8' },
  name = 'flake8',
  root_markers = {
    { '.flake8' },
    {
      'setup.cfg',
      'tox.ini',
    },
    {
      'Pipfile',
      'pyproject.toml',
      'requirements.txt',
      'setup.py',
    },
    { 'venv', 'env', '.venv', '.env' },
    { '.python-version' },
  },
  settings = {
    languages = {
      -- Source: https://github.com/creativenull/efmls-configs-nvim/blob/main/lua/efmls-configs/linters/flake8.lua
      python = {
        {
          lintSource = 'flake8',
          lintCommand = 'flake8 --ignore=E501 -', -- ignore line length error
          lintFormats = { 'stdin:%l:%c: %t%n %m' },
          lintIgnoreExitCode = true,
          lintAfterOpen = true,
          lintStdin = true,
        },
      },
    },
  },
}
