local settings = {
  analysis = {
    -- Too many warnings in default 'recommended' mode from basedpyright
    -- `typeCheckingMode` has been moved from top-level to `analysis`, see
    -- https://docs.basedpyright.com/latest/configuration/language-server-settings/
    typeCheckingMode = 'standard',
    autoSearchPaths = true,
    useLibraryCodeForTypes = true,
    diagnosticMode = 'openFilesOnly',
  },
}

if vim.fn.executable('basedpyright-langserver') == 1 then
  ---@type lsp.config
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
