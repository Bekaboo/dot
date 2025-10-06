---@type lsp.config
return {
  filetypes = { 'python' },
  cmd = { 'efm-langserver' },
  requires = { 'black' },
  root_markers = {
    { 'pyproject.toml' },
    {
      'Pipfile',
      'requirements.txt',
      'setup.cfg',
      'setup.py',
      'tox.ini',
    },
    { 'venv', 'env', '.venv', '.env' },
    { '.python-version' },
  },
  name = 'black',
  init_options = { documentFormatting = true },
  settings = {
    languages = {
      python = {
        {
          formatCommand = 'black --no-color -q -',
          formatStdin = true,
        },
      },
    },
  },
}
