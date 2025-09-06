local M = {}

---@type table<string, boolean> plugins/modules loaded
M.loaded = {}

---Load lua module for given filetype once
---@param ft string filetype to load, default to current buffer's filetype
---@param from string module to load from
---@param load fun(ft: string, ...): boolean? return `true` to re-trigger `FileType` event
function M.ft_load_once(ft, from, load)
  local mod_name = string.format('%s.%s', from, ft)
  if M.loaded[mod_name] then
    return
  end
  M.loaded[mod_name] = true

  local ok, mod = pcall(require, mod_name)
  if not ok then
    return
  end

  -- Only trigger FileType event when ft matches current buffer's ft, else
  -- it will mess up current buffer's hl and conceal
  if ft == vim.bo.ft and load(ft, mod) then
    vim.api.nvim_exec_autocmds('FileType', { pattern = ft })
  end
end

---Automatically load filetype-specific lua file from given module once
---@param from string module to load from
---@param load fun(ft: string, ...): boolean? return `true` to re-trigger `FileType` event
function M.ft_auto_load_once(from, load)
  if M.loaded[from] then
    return
  end
  M.loaded[from] = true

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    M.ft_load_once(vim.bo[buf].ft, from, load)
  end

  vim.api.nvim_create_autocmd('FileType', {
    desc = string.format('Load for filetypes from %s lazily.', from),
    group = vim.api.nvim_create_augroup('my.ft_load.' .. from, {}),
    callback = function(args)
      M.ft_load_once(args.match, from, load)
    end,
  })
end

---@class load_event_spec_structured_t
---@field event string
---@field buffer? integer
---@field desc? string
---@field nested? boolean
---@field pattern? string|string[]
---@field retrig? boolean

---@alias load_event_spec_t load_event_spec_structured_t|string

---Load plugin once on given events
---@param event_specs load_event_spec_t|load_event_spec_t[] event/list of events to load the plugin
---@param name string unique name of the plugin, also used as a namespace to prevent setting duplicated lazy-loading handlers for the same plugin/module
---@param load? boolean|(fun(args: vim.api.keyset.create_autocmd.callback_args): boolean?) function to load the plugin, returns true if the event should be re-triggered to execute corresponding event handlers in lazy-loaded plugins; if not a function, use `name` as the lua module name
function M.on_events(event_specs, name, load)
  if M.loaded[name] then
    return
  end

  local augroup_id = vim.api.nvim_create_augroup(
    string.format('my.load.on_events.%s', name),
    { clear = false }
  )

  ---@param l? boolean|(fun(args: vim.api.keyset.create_autocmd.callback_args): boolean?)
  ---@return fun(args: vim.api.keyset.create_autocmd.callback_args)
  load = (function(l)
    ---Wrapped callback that deletes the loading augroup to avoid double loading
    ---and re-triggers event to execute event handlers in lazy-loaded plugins
    ---@param args vim.api.keyset.create_autocmd.callback_args
    return function(args)
      pcall(vim.api.nvim_del_augroup_by_id, augroup_id)
      M.loaded[name] = true

      local retrig = (function()
        if l and vim.is_callable(l) then
          return l(args)
        end

        pcall(vim.cmd.packadd, name)
        pcall(require, name)

        if type(l) == 'boolean' then
          return l
        end
      end)()

      if retrig then
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(args.buf) then
            return
          end
          vim.api.nvim_buf_call(args.buf, function()
            vim.api.nvim_exec_autocmds(args.event, {
              pattern = args.match,
            })
          end)
        end)
      end
    end
  end)(load)

  -- Normalize `event_specs` to be a list of structured specs, e.g.
  -- {
  --   { event = ... },
  --   { event = ... },
  --   ...
  -- }
  ---@diagnostic disable-next-line: param-type-mismatch
  if not vim.islist(event_specs) then
    event_specs = { event_specs } ---@cast event_specs load_event_spec_t[]
  end
  for i, event_spec in ipairs(event_specs) do
    if type(event_spec) == 'string' then
      event_specs[i] = { event = event_spec }
    end
  end

  for _, event_spec in ipairs(event_specs) do
    vim.api.nvim_create_autocmd(event_spec.event, {
      once = true,
      group = augroup_id,
      buffer = event_spec.buffer,
      desc = event_spec.desc,
      nested = event_spec.nested,
      pattern = event_spec.pattern,
      callback = load,
    })
  end
end

---Load plugin once on given commands
---@param cmds string|string[] command/list of commands to load the plugin
---@param name string unique name of the plugin, also used as a namespace to prevent setting duplicated lazy-loading handlers for the same plugin/module
---@param load? function function to load the plugin
function M.on_cmds(cmds, name, load)
  if M.loaded[name] then
    return
  end

  if type(cmds) ~= 'table' then
    cmds = { cmds }
  end

  for _, cmd in ipairs(cmds) do
    ---@param l? function function to load the plugin
    ---@return function
    load = (function(l)
      return function()
        pcall(vim.api.nvim_del_user_command, cmd)
        M.loaded[name] = true

        if l and vim.is_callable(l) then
          l()
        else
          pcall(vim.cmd.packadd, name)
          pcall(require, name)
        end
      end
    end)(load)

    if vim.fn.exists(':' .. cmd) == 2 then
      goto continue
    end

    vim.api.nvim_create_user_command(cmd, function(call_args)
      load()

      -- Adapted from
      -- https://github.com/folke/lazy.nvim/blob/main/lua/lazy/core/handler/cmd.lua
      local cmd_info = vim.api.nvim_get_commands({})[cmd]
        or vim.api.nvim_buf_get_commands(0, {})[cmd]
      if not cmd_info then
        return
      end

      local cmd_call_spec = {
        cmd = cmd,
        bang = call_args.bang or nil,
        mods = call_args.smods,
        args = call_args.fargs,
        nargs = cmd_info.nargs,
        count = call_args.count >= 0
            and call_args.range == 0
            and call_args.count
          or nil,
        range = call_args.range == 1 and { call_args.line1 }
          or call_args.range == 2 and { call_args.line1, call_args.line2 }
          or nil,
      }

      if
        call_args.args
        and call_args.args ~= ''
        and cmd_info.nargs
        and cmd_info.nargs:find('[1?]')
      then
        cmd_call_spec.args = { call_args.args }
      end

      vim.cmd(cmd_call_spec)
    end, {
      bang = true,
      range = true,
      nargs = '*',
      complete = function(_, line)
        load()
        return vim.fn.getcompletion(line, 'cmdline')
      end,
    })
    ::continue::
  end
end

return M
