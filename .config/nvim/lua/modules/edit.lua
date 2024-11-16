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
    config = function()
      require('configs.nvim-surround')
    end,
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
      { 'gL', mode = { 'n', 'x' }, desc = 'Interactive align text' },
    },
    config = function()
      require('configs.vim-easy-align')
    end,
  },

  {
    'andymass/vim-matchup',
    lazy = true,
    init = function()
      -- Disable matchit and matchparen
      vim.g.loaded_matchparen = 0
      vim.g.loaded_matchit = 0

      -- Lazy-load after UIEnter
      vim.api.nvim_create_autocmd('UIEnter', {
        once = true,
        callback = vim.schedule_wrap(function()
          require('match-up').setup({ sync = true })
          vim.fn['matchup#loader#init_buffer']()
          return true
        end),
      })
    end,
    config = function()
      require('configs.vim-matchup')
    end,
  },
}
