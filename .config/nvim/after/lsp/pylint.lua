local root_markers = {
  'pylintrc',
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
  requires = { 'pylint' },
  name = 'pylint',
  root_markers = root_markers,
  settings = {
    languages = {
      python = {
        {
          lintSource = 'pylint',
          lintCommand = 'pylint --disable line-too-long,import-error --score=no --from-stdin "${INPUT}"',
          lintFormats = { '%f:%l:%c: %t%.%#: %m' },
          lintStdin = true,
          lintSeverity = 2,
          rootMarkers = root_markers,
        },
      },
    },
  },
}
