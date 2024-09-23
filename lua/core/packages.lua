if vim.env.NVIM_NO3RD then
  return
end

local utils = require('utils')
local icons = utils.static.icons
local conf_path = vim.fn.stdpath('config') --[[@as string]]
local data_path = vim.fn.stdpath('data') --[[@as string]]
local state_path = vim.fn.stdpath('state') --[[@as string]]

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
  vim.ui.input({
    prompt = '[packages] package manager not found, bootstrap? [y/N/never] ',
  }, function(r)
    response = r
  end)

  if vim.fn.match(response, '[Nn][Ee][Vv][Ee][Rr]') >= 0 then
    startup_data.bootstrap = false
    utils.json.write(startup_file, startup_data)
    return false
  end

  if vim.fn.match(response, '^[Yy]\\([Ee][Ss]\\)\\?$') < 0 then
    return false
  end

  print('\n')
  local lock_data = utils.json.read(vim.g.package_lock)
  local commit = lock_data['lazy.nvim'] and lock_data['lazy.nvim'].commit
  local url = 'https://github.com/folke/lazy.nvim.git'
  vim.notify('[packages] installing lazy.nvim...')
  vim.fn.mkdir(vim.g.package_path, 'p')
  if
    not utils.git.execute({
      'clone',
      '--filter=blob:none',
      url,
      lazy_path,
    }, vim.log.levels.INFO).success
  then
    return false
  end

  if commit then
    utils.git.dir_execute(
      lazy_path,
      { 'checkout', commit },
      vim.log.levels.INFO
    )
  end
  local lazy_patch_path =
    vim.fs.joinpath(conf_path, 'patches', 'lazy.nvim.patch')
  if vim.uv.fs_stat(lazy_patch_path) and vim.uv.fs_stat(lazy_path) then
    utils.git.dir_execute(lazy_path, {
      'apply',
      '--ignore-space-change',
      lazy_patch_path,
    }, vim.log.levels.WARN)
  end
  vim.notify('[packages] lazy.nvim cloned to ' .. lazy_path)
  vim.opt.rtp:prepend(lazy_path)
  return true
end

---Enable modules
---@param module_names string[]
local function enable_modules(module_names)
  local config = {
    root = vim.g.package_path,
    lockfile = vim.g.package_lock,
    ui = {
      backdrop = 100,
      border = vim.g.modern_ui and 'solid' or 'single',
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
        loaded = icons.CircleFilled,
        not_loaded = icons.CircleOutline,
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
    install = { colorscheme = { 'macro', 'nano', 'cockatoo' } },
  }
  local modules = {}
  for _, module_name in ipairs(module_names) do
    vim.list_extend(modules, require('modules.' .. module_name))
  end

  -- Use `=` instead of `<CR>` to view details in the floating window
  require('lazy.view.config').keys.details = '='

  require('lazy').setup(modules, config)
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

    local patches_path = vim.fs.joinpath(conf_path, 'patches')
    for patch in vim.fs.dir(patches_path) do
      local patch_path = vim.fs.joinpath(patches_path, patch)
      local plugin_path =
        vim.fs.joinpath(vim.g.package_path, (patch:gsub('%.patch$', '')))
      if vim.uv.fs_stat(plugin_path) then
        utils.git.dir_execute(plugin_path, {
          'restore',
          '.',
        })
        if not vim.endswith(info.match, 'Pre') then
          vim.notify('[packages] applying patch ' .. patch)
          utils.git.dir_execute(plugin_path, {
            'apply',
            '--ignore-space-change',
            patch_path,
          }, vim.log.levels.WARN)
        end
      end
    end
  end,
})

if vim.g.vscode then
  enable_modules({
    'lib',
    'edit',
    'treesitter',
  })
else
  enable_modules({
    'lib',
    'lsp',
    'edit',
    'debug',
    'tools',
    'markup',
    'completion',
    'treesitter',
    'colorschemes',
  })
end
