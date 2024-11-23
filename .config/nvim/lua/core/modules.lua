if vim.env.NVIM_NO3RD then
  return
end

local utils = require('utils')
local icons = utils.static.icons
local conf_path = vim.fn.stdpath('config') --[[@as string]]
local data_path = vim.fn.stdpath('data') --[[@as string]]
local state_path = vim.fn.stdpath('state') --[[@as string]]
local patches_path = vim.fs.joinpath(conf_path, 'patches')

---Run a system command synchronously and print message on error
---@param cmd string[]
---@param opts vim.SystemOpts?
---@param loglev number?
---@return boolean: success
local function system_sync(cmd, opts, loglev)
  local obj = vim.system(cmd, opts):wait()
  if obj.code ~= 0 then
    vim.notify('[modules]: ' .. obj.stderr, loglev or vim.log.levels.WARN)
    return false
  end
  return true
end

---Install package manager if not already installed
---@return boolean success
local function bootstrap()
  vim.g.package_path = vim.fs.joinpath(data_path, 'packages')
  vim.g.package_lock = vim.fs.joinpath(conf_path, 'package-lock.json')
  local lazy_path = vim.fs.joinpath(vim.g.package_path, 'lazy.nvim')
  if vim.uv.fs_stat(lazy_path) then
    vim.opt.rtp:prepend(lazy_path)
    return true
  end

  local startup_file = vim.fs.joinpath(state_path, 'startup.json')
  local startup_data = utils.json.read(startup_file)
  if startup_data.bootstrap == false then
    return false
  end

  local response = ''
  vim.ui.input(
    { prompt = '[modules] package manager not found, bootstrap? [y/N/never] ' },
    function(r)
      response = r
    end
  )

  if vim.fn.match(response, '[Nn][Ee][Vv][Ee][Rr]') >= 0 then
    startup_data.bootstrap = false
    utils.json.write(startup_file, startup_data)
    vim.notify(
      string.format(
        "\n[modules] bootstrap disabled, remove '%s' to re-enable",
        startup_file
      )
    )
    return false
  end

  if vim.fn.match(response, '^[Yy]\\([Ee][Ss]\\)\\?$') < 0 then
    return false
  end

  print('\n')
  local lock_data = utils.json.read(vim.g.package_lock)
  local commit = lock_data['lazy.nvim'] and lock_data['lazy.nvim'].commit
  local url = 'https://github.com/folke/lazy.nvim.git'
  vim.notify('[modules] installing lazy.nvim...')
  vim.fn.mkdir(vim.g.package_path, 'p')
  if
    not system_sync({ 'git', 'clone', '--filter=blob:none', url, lazy_path })
  then
    return false
  end

  if commit then
    system_sync(
      { 'git', 'checkout', commit },
      { cwd = lazy_path },
      vim.log.INFO
    )
  end
  local lazy_patch_path =
    vim.fs.joinpath(conf_path, 'patches', 'lazy.nvim.patch')
  if vim.uv.fs_stat(lazy_patch_path) and vim.uv.fs_stat(lazy_path) then
    system_sync(
      { 'git', 'apply', '--ignore-space-change', lazy_patch_path },
      { cwd = lazy_path }
    )
  end
  vim.notify(string.format("[modules] lazy.nvim cloned to '%s'", lazy_path))
  vim.opt.rtp:prepend(lazy_path)
  return true
end

---Enable modules
---@param module_names string[]? when omitted, enable all modules under `lua/modules`
local function enable_modules(module_names)
  if not module_names then
    module_names = {}
    for item in vim.fs.dir(vim.fs.joinpath(conf_path, 'lua/modules')) do
      table.insert(module_names, vim.fn.fnamemodify(item, ':r'))
    end
  end

  local modules = {}
  for _, module_name in ipairs(module_names) do
    vim.list_extend(modules, require('modules.' .. module_name))
  end

  -- Preload modified lazy.nvim modules so that they won't be loaded
  -- unpatched later on package sync
  require('lazy.manage.task.git')
  require('lazy.view.config').keys.details = '='

  require('lazy').setup(modules, {
    root = vim.g.package_path,
    lockfile = vim.g.package_lock,
    ui = {
      backdrop = 100,
      border = vim.g.has_display and 'solid' or 'single',
      size = { width = 0.7, height = 0.74 },
      icons = {
        cmd = icons.Cmd,
        config = icons.Config,
        event = icons.Event,
        debug = '',
        favorite = icons.star,
        ft = icons.File,
        init = icons.Config,
        import = icons.ArrowLeft,
        keys = icons.Keyboard,
        lazy = icons.Lazy,
        loaded = icons.Bullet1,
        not_loaded = icons.Bullet2,
        plugin = icons.Module,
        runtime = icons.File,
        require = icons.Lua,
        source = icons.Method,
        start = icons.Play,
        task = icons.Ok,
        list = { '' },
      },
    },
    checker = { enabled = false },
    change_detection = { notify = false },
    install = {
      colorscheme = {
        'macro',
        'nano',
        'sonokai',
        'cockatoo',
      },
    },
  })
end

if not bootstrap() then
  return
end

-- Reverse/Apply local patches on updating/installing plugins,
-- must be created before setting lazy to apply the patches properly
vim.api.nvim_create_autocmd('User', {
  desc = 'Reverse/Apply local patches on updating/intalling plugins.',
  group = vim.api.nvim_create_augroup('LazyPatches', {}),
  pattern = {
    'LazyInstall*',
    'LazyUpdate*',
    'LazySync*',
    'LazyRestore*',
  },
  callback = function(info)
    -- In a lazy sync action:
    -- -> LazySyncPre     <- restore packages
    -- -> LazyInstallPre
    -- -> LazyUpdatePre
    -- -> LazyInstall
    -- -> LazyUpdate
    -- -> LazySync        <- apply patches
    vim.g._lz_syncing = vim.g._lz_syncing or info.match == 'LazySyncPre'
    -- Avoid applying and reverting patches multiple times on `:LazySync` while
    -- still being able to apply and revert patches correctly for
    -- `:LazyInstall` and `:LazyUpdate`
    if vim.g._lz_syncing and not vim.startswith(info.match, 'LazySync') then
      return
    end
    if info.match == 'LazySync' then
      vim.g._lz_syncing = nil
    end

    for patch in vim.fs.dir(patches_path) do
      local patch_path = vim.fs.joinpath(patches_path, patch)
      local plugin_path =
        vim.fs.joinpath(vim.g.package_path, (patch:gsub('%.patch$', '')))
      if vim.uv.fs_stat(plugin_path) then
        system_sync({ 'git', 'restore', '.' }, { cwd = plugin_path })
        if not vim.endswith(info.match, 'Pre') then
          vim.notify(string.format("[packages] applying patch '%s'", patch))
          system_sync(
            { 'git', 'apply', '--ignore-space-change', patch_path },
            { cwd = plugin_path }
          )
        end
      end
    end
  end,
})

-- If launched in vscode, only enable basic modules
enable_modules(vim.g.vscode and {
  'lib',
  'edit',
  'treesitter',
})
