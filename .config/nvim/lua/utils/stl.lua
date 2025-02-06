local M = {}

---Get string representation of a string with highlight
---@param str? string sign symbol
---@param hl? string name of the highlight group
---@param restore? boolean restore highlight after the sign, default true
---@param force? boolean apply highlight even if 'termguicolors' is off
---@return string sign string representation of the sign with highlight
function M.hl(str, hl, restore, force)
  restore = restore == nil or restore
  -- Don't add highlight in tty to get a cleaner UI
  hl = (vim.go.termguicolors or force) and hl or ''
  return restore and table.concat({ '%#', hl, '#', str or '', '%*' })
    or table.concat({ '%#', hl, '#', str or '' })
end

---Make a winbar string clickable
---@param str string
---@param callback string
---@return string
function M.make_clickable(str, callback)
  return string.format('%%@%s@%s%%X', callback, str)
end

---Escape '%' with '%' in a string to avoid it being treated as a statusline
---field, see `:h 'statusline'`
---@param str string
---@return string
function M.escape(str)
  return (str:gsub('%%', '%%%%'))
end

---@class stl_spinner_t
---@field opts stl_spinner_opts_t
---@field timer uv.uv_timer_t
---@field icon string icon of the spinner
---@field changed_tick integer timestamp when the spinner icons is changed last time
---@field status 'spinning'|'finish'|'idle'
M.spinner = {}

---@class stl_spinner_opts_t
---@field frame_interval? integer time interval between spinner frames (ms)
---@field finish_timeout? integer time to show finish icon before clearing (ms)
---@field icons? { progress: string[], finish: string }
---@field on_spin? fun(spinner: stl_spinner_t) function to execute on each update
---@field on_finish? fun(spinner: stl_spinner_t) function to execute on stop

---@type stl_spinner_opts_t
M.spinner.default_opts = {
  frame_interval = 80,
  finish_timeout = 1000,
  icons = {
    progress = vim.g.has_nf
        and { '⣷', '⣯', '⣟', '⡿', '⢿', '⣻', '⣽', '⣾' }
      or {
        '[    ]',
        '[=   ]',
        '[==  ]',
        '[=== ]',
        '[ ===]',
        '[  ==]',
        '[   =]',
      },
    finish = vim.g.has_nf and vim.trim(require('utils.static.icons').Ok)
      or '[done]',
  },
}

---Create a new spinner instance
---@param opts stl_spinner_opts_t?
---@return stl_spinner_t
function M.spinner:new(opts)
  return setmetatable({
    opts = vim.tbl_deep_extend('keep', opts or {}, M.spinner.default_opts),
    timer = vim.uv.new_timer(),
    icon = '',
    last_change = vim.uv.now(),
    status = 'idle',
  }, { __index = self })
end

---Delete the spinner instance and clean up resources
function M.spinner:del()
  if self.status == 'spinning' then
    self:finish()
  end
  self.timer:close()
  for key, _ in pairs(self) do
    self[key] = nil
  end
end

---Start or continue spinning animation
---@param on_spin? fun(spinner: stl_spinner_t)
function M.spinner:spin(on_spin)
  on_spin = on_spin or self.opts.on_spin

  local now = vim.uv.now()

  -- Don't interrupt finish state if it hasn't displayed for
  -- `finish_timeout` ms
  if
    self.status == 'finish'
    and now - self.changed_tick < self.opts.finish_timeout
  then
    return
  end

  self.changed_tick = now
  self.icon = self.opts.icons.progress[math.ceil(
    now / self.opts.frame_interval
  ) % #self.opts.icons.progress + 1]

  -- Start timer if not already spinning
  if self.status ~= 'spinning' then
    self.status = 'spinning'
    self.timer:start(
      0,
      self.opts.frame_interval,
      vim.schedule_wrap(function()
        self:spin(on_spin)
      end)
    )
  end

  if on_spin then
    on_spin(self)
  end

  self:redraw()
end

---Show finish icon and stop spinning
---@param on_finish? fun(spinner: stl_spinner_t)
function M.spinner:finish(on_finish)
  on_finish = on_finish or self.opts.on_finish

  local now = vim.uv.now()
  if self.icon ~= self.opts.icons.finish then
    self.changed_tick = now
    self.icon = self.opts.icons.finish
  end

  -- Stop timer if spinning
  if self.status == 'spinning' then
    self.status = 'finish'
    self.timer:stop()
    if on_finish then
      on_finish(self)
    end
  end

  self:redraw()

  -- Clear the icon after timeout
  vim.defer_fn(function()
    local n = vim.uv.now()
    -- Don't clear if not in `finish` state or icon changed after this
    -- `spinner:finish()` call
    if self.status ~= 'finish' or self.changed_tick ~= now then
      return
    end
    self.changed_tick = n
    self.icon = ''
    self.status = 'idle'
    self:redraw()
  end, self.opts.finish_timeout)
end

---Redraw so that the new icon can be shown in statusline
function M.spinner.redraw()
  vim.cmd.redrawstatus({
    mods = {
      emsg_silent = true,
    },
  })
end

return M
