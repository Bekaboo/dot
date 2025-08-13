---@type lsp_config_t
return {
  filetypes = { 'python' },
  cmd = { 'efm-langserver' },
  requires = { 'mypy' },
  name = 'mypy',
  root_markers = {
    {
      'mypy.ini',
      '.mypy.ini',
    },
    {
      'pyproject.toml',
      'setup.cfg',
    },
    {
      'Pipfile',
      'requirements.txt',
      'setup.py',
      'tox.ini',
    },
    { 'venv', 'env', '.venv', '.env' },
    { '.python-version' },
  },
  settings = {
    languages = {
      -- https://github.com/creativenull/efmls-configs-nvim/blob/main/lua/efmls-configs/linters/mypy.lua
      python = {
        {
          lintSource = 'mypy',
          lintCommand = 'mypy --disable-error-code import-untyped --show-column-numbers',
          lintFormats = {
            '%f:%l:%c: %trror: %m',
            '%f:%l:%c: %tarning: %m',
            '%f:%l:%c: %tote: %m',
          },
          lintAfterOpen = true,
          -- Mypy does not support reading from stdin, see
          -- https://github.com/python/mypy/issues/12235
          lintStdin = false,
        },
      },
    },
  },
}
