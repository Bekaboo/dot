return {
  {
    'kylechui/nvim-surround',
    keys = {
      'ys',
      'ds',
      'cs',
      { 'S', mode = 'x' },
      { '<C-g>s', mode = 'i' },
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
      { 'gl', mode = { 'n', 'x' } },
      { 'gL', mode = { 'n', 'x' } },
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
          vim.opt.rtp:append(
            vim.fs.joinpath(vim.g.package_path, 'vim-matchup')
          )
          vim.cmd.runtime('plugin/matchup.vim')
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
