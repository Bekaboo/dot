local utils = require('my.utils')

local config_path = vim.fn.stdpath('config') --[[@as string]]
local specs_start_path =
  vim.fs.joinpath(config_path, 'lua/my/pack/specs/start')
local specs_opt_path = vim.fs.joinpath(config_path, 'lua/my/pack/specs/opt')

---@param path string
---@return my.pack.spec[]
local function collect_specs(path)
  local specs = {} ---@type my.pack.spec[]
  local namespace = 'my.pack.specs.' .. vim.fs.basename(path)
  for spec in vim.fs.dir(path) do
    local name = vim.fn.fnamemodify(spec, ':r')
    table.insert(specs, require(string.format('%s.%s', namespace, name)))
  end
  return specs
end

---@param spec my.pack.spec
---@return boolean
local function is_builtin(spec)
  return utils.pack.is_builtin(spec)
end

---@param specs my.pack.spec[]
---@param builtin boolean
---@return my.pack.spec[]
local function filter_specs(specs, builtin)
  return vim.tbl_filter(function(spec)
    return is_builtin(spec) == builtin
  end, specs)
end

local specs_start = collect_specs(specs_start_path)
local specs_opt ---@type my.pack.spec[]?

---@return my.pack.spec[]
local function get_specs_opt()
  if not specs_opt then
    specs_opt = collect_specs(specs_opt_path)
  end
  return specs_opt
end

-- Built-in specs under `start` are loaded during init, while those under
-- `opt` are deferred until after the UI is ready.
utils.pack.add(filter_specs(specs_start, true))
utils.load.on_events(
  'UIEnter',
  'my.pack.load_builtin_opt',
  vim.schedule_wrap(function()
    utils.pack.add(filter_specs(get_specs_opt(), true))
  end)
)

if vim.env.NVIM_NO3RD then
  return
end

local specs_start_external = filter_specs(specs_start, false)

-- Load and manage all plugin specs on startup if a file is provided to nvim
-- or plugin dir does not exist (fresh install)
if vim.fn.argc(-1) > 0 or not vim.uv.fs_stat(utils.pack.root()) then
  utils.pack.add(
    vim.list_extend(specs_start_external, filter_specs(get_specs_opt(), false))
  )
  return
end

-- Defer loading plugin specs in `opt` if no files are given
-- Specs under `start` are always loaded on startup
utils.pack.add(specs_start_external)
utils.load.on_events(
  'UIEnter',
  'my.pack.load_external_opt',
  vim.schedule_wrap(function()
    utils.pack.add(filter_specs(get_specs_opt(), false))
  end)
)
utils.load.on_events(
  { 'CmdUndefined', 'SessionLoadPost', 'FileType' },
  'my.pack.load_external_opt',
  function()
    utils.pack.add(filter_specs(get_specs_opt(), false))
  end
)
