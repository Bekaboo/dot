return {
  {
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
    cmd = {
      'TSInstall',
      'TSInstallSync',
      'TSInstallInfo',
      'TSUninstall',
      'TSUpdate',
      'TSUpdateSync',
      'TSBufEnable',
      'TSBufToggle',
      'TSEnable',
      'TSToggle',
      'TSModuleInfo',
      'TSEditQuery',
      'TSEditQueryUserAfter',
    },
    event = 'BufReadPre',
    config = function()
      vim.schedule(function()
        require('configs.nvim-treesitter')
      end)
    end,
    dependencies = {
      'nvim-treesitter/nvim-treesitter-textobjects',
      'JoosepAlviste/nvim-ts-context-commentstring',
      'RRethy/nvim-treesitter-endwise',
    },
  },

  {
    'tronikelis/ts-autotag.nvim',
    event = 'InsertEnter',
    dependencies = 'nvim-treesitter/nvim-treesitter',
    config = function()
      require('configs.ts-autotag')
    end,
  },

  {
    'Wansmer/treesj',
    cmd = { 'TSJToggle', 'TSJSplit', 'TSJJoin' },
    keys = {
      { '<M-C-K>', desc = 'Join current treesitter node' },
      { '<M-NL>', desc = 'Split current treesitter node' },
      { 'g<M-NL>', desc = 'Split current treesitter node recursively' },
    },
    dependencies = 'nvim-treesitter/nvim-treesitter',
    config = function()
      require('configs.treesj')
    end,
  },

  {
    'Eandrju/cellular-automaton.nvim',
    cmd = 'CellularAutomaton',
    dependencies = 'nvim-treesitter/nvim-treesitter',
  },
}
