local icons = require('utils.static.icons')
local wk_win = require('which-key.win')
local wk_trig = require('which-key.triggers')
local wk_plugin_regs = require('which-key.plugins.registers')
local wk_plugin_marks = require('which-key.plugins.marks')

-- Hijack `which-key.win.show()` to fix gap to the right of which-key window
-- when using helix preset
wk_win.show = (function(show_fn)
  return function(self, opts, ...)
    if opts and opts.col then
      opts.col = opts.col + 1
    end
    return show_fn(self, opts, ...)
  end
end)(wk_win.show)

-- `<M->` will be added as a trigger if keymap `<M->>` (aka alt + left-angle)
-- is set, conflicting with the default visual mode keymap `<`
-- TODO: report to upstream
---@param add_fn function
wk_trig.add = (function(add_fn)
  ---@param trig wk.Trigger
  return function(trig)
    if trig.keys == '<M->' then
      return
    end
    add_fn(trig)
  end
end)(wk_trig.add)

---Hijack `fn` to hide descriptions in its returned items
---@param fn fun(...): wk.Plugin.item[]
---@return fun(...): wk.Plugin.item[]
local function hide_desc(fn)
  return function(...)
    local items = fn(...)
    for i, _ in ipairs(items) do
      items[i].desc = ''
    end
    return items
  end
end

wk_plugin_regs.expand = hide_desc(wk_plugin_regs.expand)
wk_plugin_marks.expand = hide_desc(wk_plugin_marks.expand)

local wk = require('which-key')
wk.setup({
  preset = 'helix',
  delay = function(ctx)
    return ctx.plugin and 0 or 640
  end,
  win = { border = 'solid' },
  sort = {
    'local',
    'order',
    'group',
    'desc',
    'alphanum',
    'mod',
  },
  filter = function(mapping)
    return not mapping.lhs:find('<Esc>', 0, true)
      and not mapping.lhs:find('<.*Mouse.*>')
      and not mapping.lhs:find('<.*ScrollWheel.*>')
  end,
  defer = function(ctx)
    return ctx.mode == 'V' or ctx.mode == '<C-V>' or ctx.mode == 'v'
  end,
  plugins = {
    spelling = {
      suggestions = (function()
        for _, val in ipairs(vim.opt.spellsuggest:get()) do
          local num_suggestions = tonumber(val)
          if num_suggestions then
            return num_suggestions
          end
        end
      end)(),
    },
  },
  icons = {
    mappings = false,
    breadcrumb = '',
    separator = '',
    group = '+',
    ellipsis = icons.Ellipsis,
    keys = {
      Up = icons.keys.Up,
      Down = icons.keys.Down,
      Left = icons.keys.Left,
      Right = icons.keys.Right,
      C = icons.keys.Control,
      M = icons.keys.Meta,
      D = icons.keys.Command,
      S = icons.keys.Shift,
      CR = icons.keys.Enter,
      Esc = icons.keys.Escape,
      ScrollWheelDown = icons.keys.MouseDown,
      ScrollWheelUp = icons.keys.MouseUp,
      NL = icons.keys.Enter,
      BS = icons.keys.BackSpace,
      Space = icons.keys.Space,
      Tab = icons.keys.Tab,
      F1 = icons.keys.F1,
      F2 = icons.keys.F2,
      F3 = icons.keys.F3,
      F4 = icons.keys.F4,
      F5 = icons.keys.F5,
      F6 = icons.keys.F6,
      F7 = icons.keys.F7,
      F8 = icons.keys.F8,
      F9 = icons.keys.F9,
      F10 = icons.keys.F10,
      F11 = icons.keys.F11,
      F12 = icons.keys.F11,
    },
  },
})

wk.add({
  { '<Leader>g', group = 'Git' },
  { '<Leader>f', group = 'Find' },
  { '<Leader>fg', group = 'Git' },
  { '<Leader>fS', group = 'LSP' },
  { '<Leader>G', group = 'Debug' },
  { '<Leader>t', group = 'Table mode' },
  { '<Leader>td', group = 'Delete' },
  { '<Leader>ti', group = 'Insert' },
  { '<Leader>tf', group = 'Formula' },
  { '<LocalLeader>l', group = 'TeX' },
})

---Set default highlight groups for which-key.nvim
---@return nil
local function set_default_hlgroups()
  -- Ensure visibility in tty
  if not vim.go.termguicolors then
    vim.api.nvim_set_hl(0, 'WhichKey', { link = 'Normal', default = true })
    vim.api.nvim_set_hl(0, 'WhichKeyDesc', { link = 'Normal', default = true })
    vim.api.nvim_set_hl(
      0,
      'WhichKeySeparator',
      { link = 'WhichKeyGroup', default = true }
    )
  end
end

set_default_hlgroups()
vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('WhichKeySetDefaultHlgroups', {}),
  desc = 'Set default highlight groups for which-key.nvim.',
  callback = set_default_hlgroups,
})

vim.api.nvim_create_autocmd('ModeChanged', {
  desc = 'Redraw statusline shortly after mode change to ensure correct mode display after enting visual mode when which-key.nvim is enabled.',
  group = vim.api.nvim_create_augroup('WhichKeyRedrawStatusline', {}),
  callback = vim.schedule_wrap(function()
    vim.cmd.redrawstatus({
      mods = { emsg_silent = true },
    })
  end),
})
