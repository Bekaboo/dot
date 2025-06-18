return {
  filetypes = { 'python' },
  cmd = { 'pyre', 'persistent' },
  root_markers = {
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
  },
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
