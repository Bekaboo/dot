return {
  filetypes = { 'python' },
  cmd = { 'ruff', 'server' },
  buf_support = false,
  root_markers = {
    'ruff.toml',
    '.ruff.toml',
    'Pipfile',
    'pyproject.toml',
    'requirements.txt',
    'setup.cfg',
    'setup.py',
    'tox.ini',
  },
}
