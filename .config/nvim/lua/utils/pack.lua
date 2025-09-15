local M = {}

---Merged plugin specs indexed by plugin src
---@type table<string, vim.pack.Spec>
local specs_registry = {}

---@param spec vim.pack.Spec
---@return string
function M.get_name(spec)
  return (
    vim.fs
      .basename(spec.name or spec.src)
      :lower()
      :gsub('%.nvim$', '')
      :gsub('%.', '-')
  )
end

---Load a plugin with init, pre/post hooks, dependencies etc.
---@param spec vim.pack.Spec
---@param _? string
function M.load(spec, _)
  spec.data = spec.data or {}

  -- Dependencies must be loaded before current plugin
  if spec.data.deps then
    if not vim.islist(spec.data.deps) then
      spec.data.deps = { spec.data.deps }
    end
    for _, dep in ipairs(spec.data.deps) do
      M.load(specs_registry[type(dep) == 'string' and dep or dep.src])
    end
  end

  local plugin_name = M.get_name(spec)
  spec.data.preload = spec.data.preload
    or function()
      require('pack.preload.' .. plugin_name)
    end
  spec.data.postload = spec.data.postload
    or function()
      require('pack.postload.' .. plugin_name)
    end

  pcall(spec.data.preload)
  pcall(vim.cmd.packadd, vim.fs.basename(spec.src))
  pcall(require, plugin_name)
  pcall(spec.data.postload)
end

---Lazy-load plugin for given plugin spec
---@param spec vim.pack.Spec
---@param _ string
function M.lazy_load(spec, _)
  if not spec.data then
    M.load(spec)
    return
  end

  if spec.data.init then
    spec.data.init()
  end

  ---Whether the plugin is lazy-loaded
  ---Some plugin may set `spec.data.lazy` to `true` without setting
  ---cmd/key/event triggers to serve as a 'library'
  local lazy = spec.data.lazy

  for _, trig in ipairs({ 'cmds', 'keys', 'events' }) do
    if not spec.data[trig] then
      goto continue
    end
    lazy = true
    require('utils.load')['on_' .. trig](spec.data[trig], spec.src, function()
      M.load(spec)
    end)
    ::continue::
  end

  if not lazy then
    M.load(spec)
  end
end

---Register single plugin spec with lazy-loading, dependencies, etc.
---Helper function of `add()`
---@param spec vim.pack.Spec
function M.register_spec(spec)
  if spec.data and spec.data.deps then
    M.register(spec.data.deps)
  end

  specs_registry[spec.src] =
    vim.tbl_deep_extend('keep', spec, specs_registry[spec.src] or {})
end

---Add specified plugin spec with lazy-loading
---@param specs string|vim.pack.Spec|(string|vim.pack.Spec)[]
function M.register(specs)
  if not vim.islist(specs) then
    specs = { specs } ---@cast specs (string|vim.pack.Spec)[]
  end
  for i, spec in ipairs(specs) do
    if type(spec) == 'string' then
      specs[i] = { src = spec } ---@cast specs vim.pack.Spec[]
    end
  end

  for _, spec in ipairs(specs) do
    M.register_spec(spec)
  end
end

---Build plugin, e.g. build c/rust lib, install node dependencies, etc.
---comment
---@param spec vim.pack.Spec
---@param path string
---@param notify? boolean default to `true`
function M.build(spec, path, notify)
  if not spec.data or not spec.data.build then
    return
  end

  notify = notify ~= false
  if notify then
    vim.notify(string.format('[utils.pack] Building %s', spec.src))
  end

  -- Build can be a function, a vim command (starting with ':'), or a shell
  -- command
  if vim.is_callable(spec.data.build) then
    spec.data.build(spec, path)
    return
  end

  if
    type(spec.data.build) == 'string'
    and vim.startswith(spec.data.build, ':')
  then
    vim.cmd(spec.data.build:gsub('^:', ''))
    return
  end

  local o = vim
    .system(
      type(spec.data.build) == 'table' and spec.data.build
        or { 'sh', '-c', spec.data.build },
      { cwd = path }
    )
    :wait()
  if o.code ~= 0 then
    vim.notify(
      string.format(
        '[utils.pack] Error building plugin %s (exited with code %d): %s',
        spec.src,
        o.code,
        o.stderr
      ),
      vim.log.levels.ERROR
    )
  end
end

local pack_add = vim.pack.add

---Wrapper of `vim.pack.add()` that handles lazy-loading, dependencies, etc.
---via the `data` field
---@param specs string|vim.pack.Spec|(string|vim.pack.Spec)[]
function M.add(specs)
  M.register(specs)

  -- Set autocmd to build plugin on pack changed (installed/updated)
  vim.api.nvim_create_autocmd('PackChanged', {
    group = vim.api.nvim_create_augroup('my.pack.build', { clear = false }),
    callback = function(args)
      if args.data.kind == 'delete' then
        return
      end
      M.build(args.data.spec, args.data.path)
    end,
  })

  specs = {}
  for _, spec in pairs(specs_registry) do
    table.insert(specs, spec)
  end

  pack_add(specs, {
    load = function(args)
      (args.spec.data and args.spec.data.load or M.lazy_load)(
        args.spec,
        args.path
      )
    end,
  })
end

return M
