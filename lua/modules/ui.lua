return {
  {
    'karb94/neoscroll.nvim',
    keys = {
      '<C-y>',
      '<C-e>',
      '<C-b>',
      '<C-f>',
      '<C-u>',
      '<C-d>',
      '<S-Up>',
      '<S-Down>',
      '<PageUp>',
      '<PageDown>',
      '<S-PageUp>',
      '<S-PageDown>',
      'zb',
      'zt',
      'zz',
    },
    config = function()
      require('configs.neoscroll')
    end,
  },
}
