local root_markers = {
  { '.pyre_configuration' },
  { '.watchmanconfig' },
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
}

-- Pyre lsp requires a watchman config file, so prefer using bare pyre linter
-- with efm-langserver to avoid scattering untracked watchman config files
-- everywhere
if vim.fn.executable('efm-langserver') == 1 then
  ---@type lsp_config_t
  return {
    filetypes = { 'python' },
    cmd = { 'efm-langserver' },
    requires = { 'pyre' },
    root_markers = root_markers,
    settings = {
      languages = {
        python = {
          {
            lintSource = 'pyre',
            lintCommand = 'pyre',
            lintFormats = { '%f:%l:%c %m' },
            lintStdin = false,
            lintWorkSpace = true,
            lintOffsetColumns = 1,
            lintAfterOpen = true,
            lintIgnoreExitCode = true,
          },
        },
      },
    },
  }
end

---@type lsp_config_t
return {
  filetypes = { 'python' },
  cmd = { 'pyre', 'persistent' },
  root_markers = root_markers,
  before_init = function(params)
    if not params.rootPath or vim.fn.isdirectory(params.rootPath) == 0 then
      return
    end
    local wm_config = vim.fs.joinpath(params.rootPath, '.watchmanconfig')
    if vim.uv.fs_stat(wm_config) then
      return
    end
    -- Pyre lsp requires a watchman config under project root directory
    require('utils.json').write(wm_config, {})
  end,
}
