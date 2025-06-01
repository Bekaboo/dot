local root_markers = {
  '.isort.cfg',
  'Pipfile',
  'pyproject.toml',
  'requirements.txt',
  'setup.cfg',
  'setup.py',
  'tox.ini',
}

return {
  filetypes = { 'python' },
  cmd = { 'efm-langserver' },
  requires = { 'isort' },
  root_markers = root_markers,
  name = 'isort',
  init_options = { documentFormatting = true },
  settings = {
    languages = {
      python = {
        {
          formatCommand = 'isort --quiet -',
          formatStdin = true,
          rootMarkers = root_markers,
        },
      },
    },
  },
}
