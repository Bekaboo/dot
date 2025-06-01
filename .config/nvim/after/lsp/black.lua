return {
  filetypes = { 'python' },
  cmd = { 'efm-langserver' },
  requires = { 'black' },
  root_markers = {
    'Pipfile',
    'pyproject.toml',
    'requirements.txt',
    'setup.cfg',
    'setup.py',
    'tox.ini',
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
