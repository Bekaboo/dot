return {
  src = 'https://github.com/kylechui/nvim-surround',
  data = {
    keys = {
      { lhs = 'ys', desc = 'Surround' },
      { lhs = 'yss', desc = 'Surround line' },
      { lhs = 'yS', desc = 'Surround in new lines' },
      { lhs = 'ySS', desc = 'Surround line in new lines' },
      { lhs = 'ds', desc = 'Delete surrounding' },
      { lhs = 'cs', desc = 'Change surrounding' },
      { lhs = 'S', mode = 'x', desc = 'Surround' },
      { lhs = 'gS', mode = 'x', desc = 'Surround in new lines' },
      { lhs = '<C-g>s', mode = 'i', desc = 'Surround' },
      { lhs = '<C-g>S', mode = 'i', desc = 'Surround' },
    },
  },
}

