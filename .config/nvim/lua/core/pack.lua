if vim.env.NVIM_NO3RD then
  return
end

local conf_path = vim.fn.stdpath('config') --[[@as string]]
local state_path = vim.fn.stdpath('state') --[[@as string]]

vim.g.startup_file = vim.fs.joinpath(state_path, 'startup.json')

---Enable plugins
---@param module_names string[]? when omitted, enable all plugins under
---`lua/pack/specs`
local function enable_plugins(module_names)
  local specs_path = vim.fs.joinpath(conf_path, 'lua/pack/specs')

  if not module_names then
    module_names = {}
    for item in vim.fs.dir(specs_path) do
      table.insert(module_names, vim.fn.fnamemodify(item, ':r'))
    end
  end

  local specs = {} ---@type LazyPluginSpec[]
  for _, module_name in ipairs(module_names) do
    vim.list_extend(
      specs,
      dofile(vim.fs.joinpath(specs_path, module_name .. '.lua'))
    )
  end

  ---Wrapper function to defer plugin manager setup
  ---default to setup immediately
  ---@param cb function
  ---@return nil
  local function defer(cb)
    cb()
  end

  -- If no files are specified, defer plugin manager setup
  if vim.fn.argc(-1) == 0 then
    ---@param cb function
    ---@return nil
    defer = function(cb)
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
          local repo = type(spec[1]) == 'string' and spec[1] or nil
          local name = spec.name
            or repo and vim.fs.basename(repo)
            or spec.dir and vim.fs.basename(spec.dir)
            or 'unknown'
          local dir = spec.dir and vim.fs.normalize(spec.dir)
            or repo and vim.fs.joinpath(
              vim.g.package_path,
              vim.fs.basename(repo)
            )
            or name and vim.fs.joinpath(vim.g.package_path, name)
            or vim.g.package_path

          local plugin = {
            [1] = repo,
            name = name,
            dir = dir,
            enabled = spec.enabled ~= false,
            lazy = spec.lazy,
            event = spec.event,
            cmd = spec.cmd,
            ft = spec.ft,
            keys = spec.keys,
            init = nil, -- prevent recursion
            config = spec.config,
            build = spec.build,
            main = spec.main,
            opts = spec.opts,
            dependencies = spec.dependencies,
            specs = specs,
          }

          spec.init(plugin)
          spec.init = nil
        end
      end

      local groupid = vim.api.nvim_create_augroup('my.plugins.defer', {})

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
          callback = function(args)
            vim.api.nvim_del_augroup_by_id(groupid)
            cb()
            vim.api.nvim_exec_autocmds(args.event, { pattern = args.match })
          end,
        }
      )

      -- Defer setup until UIEnter
      vim.api.nvim_create_autocmd('UIEnter', {
        once = true,
        group = groupid,
        callback = function(args)
          vim.api.nvim_del_autocmd(args.id)
          vim.schedule(cb)
        end,
      })
    end
  end

  defer(function()
    require('utils.pack').add(specs)
  end)
end

-- If launched in vscode, only enable basic plugins
enable_plugins(vim.g.vscode and { 'edit', 'treesitter' })
