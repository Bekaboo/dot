local root_markers = {
  'pyrightconfig.json',
  'Pipfile',
  'pyproject.toml',
  'requirements.txt',
  'setup.cfg',
  'setup.py',
  'tox.ini',
}

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
  return {
    filetypes = { 'python' },
    cmd = { 'basedpyright-langserver', '--stdio' },
    root_markers = root_markers,
    settings = { basedpyright = settings },
  }
end

return {
  filetypes = { 'python' },
  cmd = { 'pyright-langserver', '--stdio' },
  root_markers = root_markers,
  settings = { python = settings },
}
