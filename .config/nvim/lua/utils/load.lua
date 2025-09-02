local M = {}

---Load for given filetype once
---@param ft string filetype to load, default to current buffer's filetype
---@param from string module to load from
---@param action fun(ft: string, ...): boolean return `true` to indicate a successful load
---@return boolean
function M.ft_load_once(ft, from, action)
  local file = string.format('%s.%s', from, ft)
  if package.loaded[file] then
    return false
  end
  local ok, val = pcall(require, file)
  if not ok or not action(ft, val) then
    return false
  end
  -- Only trigger FileType event when ft matches curent buffer's ft, else
  -- it will mess up current buffer's hl and conceal
  if ft == vim.bo.ft then
    vim.api.nvim_exec_autocmds('FileType', { pattern = ft })
  end
  return true
end

---Automatically load filetype-specific file from given module once
---@param from string module to load from
---@param action fun(ft: string, ...): boolean? return `true` to indicate a successful load
function M.ft_auto_load_once(from, action)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    M.ft_load_once(vim.bo[buf].ft, from, action)
  end

  vim.api.nvim_create_autocmd('FileType', {
    desc = string.format('Load for filetypes from %s lazily.', from),
    group = vim.api.nvim_create_augroup('my.ft_load.' .. from, {}),
    callback = function(args)
      M.ft_load_once(args.match, from, action)
    end,
  })
end

---@class load_event_spec_structured_t
---@field event string
---@field buffer? integer
---@field desc? string
---@field nested? boolean
---@field pattern? string|string[]
---@field schedule? boolean whether the callback should scheduled to next event loop

---@alias load_event_spec_t load_event_spec_structured_t|string

---Load plugin once on given events
---@param event_specs load_event_spec_t|load_event_spec_t[] event/list of events to load the plugin
---@param cb fun(args: vim.api.keyset.create_autocmd.callback_args): boolean? return true if the event should be re-triggered to execute corresponding event handlers in lazy-loaded plugins
---@return integer # augroup id
function M.on_events(event_specs, cb)
  local augroup_id = vim.api.nvim_create_augroup(
    string.format('my.load.on_events.%s', vim.uv.hrtime()),
    {}
  )

  cb = (function(c)
    ---Wrapped callback that deletes the loading augroup to avoid double loading
    ---and re-triggers event to execute event handlers in lazy-loaded plugins
    ---@param args vim.api.keyset.create_autocmd.callback_args
    return function(args)
      pcall(vim.api.nvim_del_augroup_by_id, augroup_id)
      if c(args) then
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
  end)(cb)

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
      callback = event_spec.schedule and vim.schedule_wrap(cb) or cb,
    })
  end

  return augroup_id
end

return M
