return {
  {
    'kylechui/nvim-surround',
    keys = {
      { 'ys', desc = 'Surround' },
      { 'yss', desc = 'Surround line' },
      { 'yS', desc = 'Surround in new lines' },
      { 'ySS', desc = 'Surround line in new lines' },
      { 'ds', desc = 'Delete surrounding' },
      { 'cs', desc = 'Change surrounding' },
      { 'S', mode = 'x', desc = 'Surround' },
      { 'gS', mode = 'x', desc = 'Surround in new lines' },
      { '<C-g>s', mode = 'i', desc = 'Surround' },
      { '<C-g>S', mode = 'i', desc = 'Surround' },
    },
    config = true,
  },

  {
    'tpope/vim-sleuth',
    event = { 'BufReadPre', 'StdinReadPre' },
  },

  {
    'altermo/ultimate-autopair.nvim',
    event = { 'InsertEnter', 'CmdlineEnter' },
    config = function()
      require('configs.ultimate-autopair')
    end,
  },

  {
    'junegunn/vim-easy-align',
    keys = {
      { 'gl', mode = { 'n', 'x' }, desc = 'Align text' },
      { 'gL', mode = { 'n', 'x' }, desc = 'Align text interactively' },
    },
    config = function()
      require('configs.vim-easy-align')
    end,
  },

  {
    'flwyd/vim-conjoin',
    keys = {
      { 'J', mode = { 'n', 'x' }, desc = 'Join lines' },
      {
        'gJ',
        mode = { 'n', 'x' },
        desc = 'Join lines without inserting/removing spaces',
      },
    },
  },
}
