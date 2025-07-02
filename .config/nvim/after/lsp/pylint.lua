local root_markers = {
  { 'pylintrc' },
  {
    'Pipfile',
    'pyproject.toml',
    'requirements.txt',
    'setup.cfg',
    'setup.py',
    'tox.ini',
  },
  { 'venv', 'env', '.venv', '.env' },
  { '.python-version' },
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
          lintAfterOpen = true,
          lintStdin = true,
          lintSeverity = 3,
          rootMarkers = vim.iter(root_markers):flatten():totable(),
        },
      },
    },
  },
}
