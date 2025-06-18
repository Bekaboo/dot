return {
  filetypes = { 'python' },
  cmd = { 'jedi-language-server' },
  root_markers = {
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
  },
}
