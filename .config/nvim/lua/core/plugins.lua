if vim.env.NVIM_NO3RD then
  return
end

local conf_path = vim.fn.stdpath('config') --[[@as string]]
local data_path = vim.fn.stdpath('data') --[[@as string]]
local state_path = vim.fn.stdpath('state') --[[@as string]]

vim.g.package_path = vim.fs.joinpath(data_path, 'packages')
vim.g.package_lock = vim.fs.joinpath(conf_path, 'package-lock.json')
vim.g.startup_file = vim.fs.joinpath(state_path, 'startup.json')

---Run a system command synchronously and print message on error
---@param cmd string[]
---@param opts vim.SystemOpts?
---@param loglev number?
---@return boolean: success
local function system_sync(cmd, opts, loglev)
  local obj = vim.system(cmd, opts):wait()
  if obj.code ~= 0 then
    vim.notify('[plugins] ' .. obj.stderr, loglev or vim.log.levels.WARN)
    return false
  end
  return true
end

---Install package manager if not already installed
---@return boolean success
local function bootstrap()
  local lazy_path = vim.fs.joinpath(vim.g.package_path, 'lazy.nvim')
  if vim.fn.isdirectory(lazy_path) == 1 then
    vim.opt.rtp:prepend(lazy_path)
    return true
  end

  local json = require('utils.json')
  local startup_file = vim.fs.joinpath(state_path, 'startup.json')
  local startup_data = json.read(startup_file)
  if startup_data.bootstrap == false then
    return false
  end

  local response = vim.fn.confirm(
    '[plugins] package manager not found, bootstrap?',
    '&Yes\n&No\nN&ever',
    2
  )

  -- 'No'
  if response == 0 or response == 2 then
    return false
  end

  -- 'Never'
  if response == 3 then
    startup_data.bootstrap = false
    json.write(startup_file, startup_data)
    vim.notify(
      string.format(
        "[plugins] bootstrap disabled, remove '%s' to re-enable",
        startup_file
      )
    )
    return false
  end

  -- 'Yes'
  local lock_data = json.read(vim.g.package_lock)
  local commit = lock_data['lazy.nvim'] and lock_data['lazy.nvim'].commit
  local url = 'https://github.com/folke/lazy.nvim.git'
  vim.notify('[plugins] installing lazy.nvim...')
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
  vim.notify(string.format("[plugins] lazy.nvim cloned to '%s'", lazy_path))
  vim.opt.rtp:prepend(lazy_path)
  return true
end

---Enable plugins
---@param module_names string[]? when omitted, enable all plugins under
---`lua/plugins`
local function enable_plugins(module_names)
  local plugins_path = vim.fs.joinpath(conf_path, 'lua/plugins')

  if not module_names then
    module_names = {}
    for item in vim.fs.dir(plugins_path) do
      table.insert(module_names, vim.fn.fnamemodify(item, ':r'))
    end
  end

  local specs = {} ---@type LazyPluginSpec[]
  for _, module_name in ipairs(module_names) do
    vim.list_extend(
      specs,
      dofile(vim.fs.joinpath(plugins_path, module_name .. '.lua'))
    )
  end

  ---Wrapper function to defer plugin manager setup,
  ---default to setup immediately
  ---@param setup function
  ---@return nil
  local function defer(setup)
    setup()
  end

  -- If no files are specified, defer plugin manager setup
  if vim.fn.argc(-1) == 0 then
    ---@param setup function
    ---@return nil
    defer = function(setup)
      for _, spec in ipairs(specs) do
        if
          spec.lazy == false
          or (
            spec.lazy ~= true
            and not spec.ft
            and not spec.cmd
            and not spec.keys
            and not spec.event
          )
        then
          vim.opt.rtp:append(
            spec[1]
                and vim.fs.joinpath(
                  vim.g.package_path,
                  vim.fs.basename(spec[1])
                )
              or spec.name and vim.fs.join(
                vim.g.package_path,
                vim.fs.basename(spec.name)
              )
              or spec.dir and vim.fs.normalize(spec.dir)
              or ''
          )
        end

        if spec.init then
          spec.init()
          spec.init = nil
        end
      end

      local groupid = vim.api.nvim_create_augroup('PluginDeferSetup', {})

      -- If we have undefined commands (possibly from a plugin),
      -- setup the plugin manager immediately to get the commands
      -- We might also need to load plugins (e.g. oil.nvim or vim-fugitive)
      -- on session load to load special buffers (oil:// or fugitive://)
      -- or on filetype for ftplugins
      vim.api.nvim_create_autocmd(
        { 'CmdUndefined', 'SessionLoadPost', 'FileType' },
        {
          once = true,
          group = groupid,
          callback = function(info)
            vim.api.nvim_del_augroup_by_id(groupid)
            setup()
            vim.api.nvim_exec_autocmds(info.event, { pattern = info.match })
          end,
        }
      )

      -- Defer setup until UIEnter
      vim.api.nvim_create_autocmd('UIEnter', {
        once = true,
        group = groupid,
        callback = function()
          vim.api.nvim_del_augroup_by_id(groupid)
          require('lazy.stats').on_ui_enter()
          vim.schedule(setup)
        end,
      })
    end
  end

  defer(function()
    local icons = require('utils.static.icons')
    require('lazy').setup(specs, {
      root = vim.g.package_path,
      lockfile = vim.g.package_lock,
      ui = {
        border = 'solid',
        size = { width = 0.7, height = 0.7 },
        icons = {
          cmd = icons.Cmd,
          config = icons.Config,
          event = icons.Event,
          debug = '',
          favorite = icons.Star,
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
      install = { colorscheme = { 'wildcharm' } },
      performance = {
        rtp = {
          disabled_plugins = {
            '2html_plugin',
            'compiler',
            'ftplugin',
            'gzip',
            'matchit',
            'rplugin',
            'spellfile_plugin',
            'synmenu',
            'syntax',
            'tar',
            'tarPlugin',
            'tohtml',
            'tutor',
            'zip',
            'zipPlugin',
          },
        },
      },
    })
  end)
end

if not bootstrap() then
  return
end

-- If launched in vscode, only enable basic plugins
enable_plugins(vim.g.vscode and { 'edit', 'treesitter' })
