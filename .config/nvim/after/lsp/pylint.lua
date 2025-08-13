---@type lsp_config_t
return {
  filetypes = { 'python' },
  cmd = { 'efm-langserver' },
  requires = { 'pylint' },
  name = 'pylint',
  root_markers = {
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
  },
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
        },
      },
    },
  },
}
