return {
  {
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
  },

  {
    src = 'https://github.com/tpope/vim-sleuth',
    data = {
      events = { 'BufReadPre', 'StdinReadPre' },
    },
  },

  {
    src = 'https://github.com/altermo/ultimate-autopair.nvim',
    data = {
      events = { 'InsertEnter', 'CmdlineEnter' },
    },
  },

  {
    src = 'https://github.com/junegunn/vim-easy-align',
    data = {
      keys = {
        { lhs = 'gl', mode = { 'n', 'x' }, desc = 'Align text' },
        { lhs = 'gL', mode = { 'n', 'x' }, desc = 'Align text interactively' },
      },
    },
  },

  {
    src = 'https://github.com/flwyd/vim-conjoin',
    data = {
      keys = {
        { lhs = 'J', mode = { 'n', 'x' }, desc = 'Join lines' },
        {
          lhs = 'gJ',
          mode = { 'n', 'x' },
          desc = 'Join lines without inserting/removing spaces',
        },
      },
    },
  },
}
