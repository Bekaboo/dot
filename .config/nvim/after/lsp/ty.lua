-- Python type checker and language server
-- https://github.com/astral-sh/ty

---@type lsp_config_t
return {
  filetypes = { 'python' },
  cmd = { 'ty', 'server' },
  root_markers = {
    { 'ty.toml' },
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
}
