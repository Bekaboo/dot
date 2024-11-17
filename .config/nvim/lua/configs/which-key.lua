local icons = require('utils.static.icons')

require('which-key').setup({
  preset = 'helix',
  delay = 640,
  win = { border = 'solid' },
  sort = {
    'local',
    'order',
    'group',
    'desc',
    'alphanum',
    'mod',
  },
  defer = function(ctx)
    return ctx.mode == 'V' or ctx.mode == '<C-V>' or ctx.mode == 'v'
  end,
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

local wk = require('which-key')
wk.add({
  { '<Leader>g', group = 'Git' },
  { '<Leader>f', group = 'Find' },
  { '<Leader>G', group = 'Debug' },
  { '<Leader><Leader>', group = 'Extra' },
})
