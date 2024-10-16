if vim.env.NVIM_NO3RD then
  return
end

local utils = require('utils')
local icons = utils.static.icons
local conf_path = vim.fn.stdpath('config') --[[@as string]]
local data_path = vim.fn.stdpath('data') --[[@as string]]
local state_path = vim.fn.stdpath('state') --[[@as string]]
local patches_path = vim.fs.joinpath(conf_path, 'patches')

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

---Override package manager's internal configurations and functions
---@return nil
local function override()
  -- Use `=` instead of `<CR>` to view details in the floating window
  require('lazy.view.config').keys.details = '='

  -- Ignore patched plugins in `:Lazy check`
  ---@async
  ---@diagnostic disable: undefined-field, missing-fields
  require('lazy.manage.task.git').status.run = function(self)
    self:spawn('git', {
      args = { 'ls-files', '-d', '-m' },
      cwd = self.plugin.dir,
      on_exit = function(ok, output)
        if not ok then
          return
        end

        ---@type string[]
        local lines = vim.tbl_filter(function(line)
          -- Fix doc/tags being marked as modified
          if line:gsub('[\\/]', '/') == 'doc/tags' then
            local process = require('lazy.manage.process')
            process.exec(
              { 'git', 'checkout', '--', 'doc/tags' },
              { cwd = self.plugin.dir }
            )
            return false
          end
          return line ~= ''
        end, vim.split(output, '\n'))

        if #lines == 0 then
          return
        end

        local patch_path =
          vim.fs.joinpath(patches_path, self.plugin.name .. '.patch')
        local patch_stat = vim.uv.fs_stat(patch_path)
        -- Do not warn about local changes if there is a patch file
        if not patch_stat or patch_stat.type ~= 'file' then
          local msg =
            { 'You have local changes in `' .. self.plugin.dir .. '`:' }
          for _, line in ipairs(lines) do
            msg[#msg + 1] = '  * ' .. line
          end
          msg[#msg + 1] = 'Please remove them to update.'
          msg[#msg + 1] =
            'You can also press `x` to remove the plugin and then `I` to install it again.'
          self:error(msg)
        end
      end,
    })
    ---@diagnostic enable: undefined-field, missing-fields
  end
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

  override()
  require('lazy').setup(modules, {
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
    install = {
      colorscheme = {
        'nano',
        'macro',
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
  enable_modules()
end
