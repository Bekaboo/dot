local settings = {
  -- Too many warnings in default 'recommended' mode from basedpyright
  typeCheckingMode = 'standard',
  analysis = {
    autoSearchPaths = true,
    useLibraryCodeForTypes = true,
    diagnosticMode = 'openFilesOnly',
  },
}

if vim.fn.executable('basedpyright-langserver') == 1 then
  ---@type lsp_config_t
  return {
    filetypes = { 'python' },
    cmd = { 'basedpyright-langserver', '--stdio' },
    root_markers = {
      { 'pyrightconfig.json' },
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
    settings = { basedpyright = settings },
  }
end

return {
  filetypes = { 'python' },
  cmd = { 'pyright-langserver', '--stdio' },
  root_markers = {
    { 'pyrightconfig.json' },
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
  settings = { python = settings },
}
