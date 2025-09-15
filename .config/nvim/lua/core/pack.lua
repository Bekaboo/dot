if vim.env.NVIM_NO3RD then
  return
end

local utils = require('utils')

---@param path string
---@return vim.pack.Spec[]
local function collect_specs(path)
  local specs = {} ---@type vim.pack.Spec[]
  for spec in vim.fs.dir(path) do
    table.insert(specs, dofile(vim.fs.joinpath(path, spec)))
  end
  return specs
end

---Enable plugins
---@param plugins string[]? when omitted, enable all plugins under
---`lua/pack/specs`
local function enable_plugins(plugins)
  local config_path = vim.fn.stdpath('config') --[[@as string]]

  if vim.fn.argc(-1) > 0 then
    utils.pack.add(
      vim.list_extend(
        collect_specs(vim.fs.joinpath(config_path, 'lua/pack/specs/start')),
        collect_specs(vim.fs.joinpath(config_path, 'lua/pack/specs/opt'))
      )
    )
    return
  end

  -- Defer plugin manager setup if no files are specified
  utils.pack.add(
    collect_specs(vim.fs.joinpath(config_path, 'lua/pack/specs/start'))
  )

  ---Load plugin specs under `opt` directory
  local function load_opt()
    utils.pack.add(
      collect_specs(vim.fs.joinpath(config_path, 'lua/pack/specs/opt'))
    )
  end

  utils.load.on_events('UIEnter', 'my.pack.load', vim.schedule_wrap(load_opt))
  utils.load.on_events(
    { 'CmdUndefined', 'SessionLoadPost', 'FileType' },
    'my.pack.load',
    load_opt
  )
end

-- If launched in vscode, only enable basic plugins
-- TODO: implement plugin param
enable_plugins(vim.g.vscode and { 'edit', 'treesitter' })
