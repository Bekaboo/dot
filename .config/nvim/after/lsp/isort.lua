---@type lsp.config
return {
  filetypes = { 'python' },
  cmd = { 'efm-langserver' },
  requires = { 'isort' },
  root_markers = {
    { '.isort.cfg' },
    {
      'pyproject.toml',
      'setup.cfg',
      'tox.ini',
    },
    { '.editorconfig' },
    {
      'Pipfile',
      'requirements.txt',
      'setup.py',
    },
    { 'venv', 'env', '.venv', '.env' },
    { '.python-version' },
  },
  name = 'isort',
  init_options = { documentFormatting = true },
  settings = {
    languages = {
      python = {
        {
          formatCommand = 'isort --quiet -',
          formatStdin = true,
        },
      },
    },
  },
}
