return {
  {
    'nvim-treesitter/nvim-treesitter',
    build = function()
      local ts_install_ok, ts_install =
        pcall(require, 'nvim-treesitter.install')
      if ts_install_ok then
        ts_install.update()
      end
    end,
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
    event = 'FileType',
    -- Some parsers, e.g. cuda parsers can slow down file reading speed
    -- if loaded on `FileType` event, so defer setting up nvim-treesitter
    -- to first read the file then enable treesitter afterwards
    config = vim.schedule_wrap(function()
      require('configs.nvim-treesitter')
    end),
  },

  {
    'nvim-treesitter/nvim-treesitter-textobjects',
    dependencies = 'nvim-treesitter/nvim-treesitter',
    event = 'FileType',
    -- Plugins that require nvim-treesitter and loaded on `FileType` must be scheduled
    -- as well to avoid loading nvim-treesitter early
    config = vim.schedule_wrap(function()
      require('configs.nvim-treesitter-textobjects')
    end),
  },

  {
    'RRethy/nvim-treesitter-endwise',
    dependencies = 'nvim-treesitter/nvim-treesitter',
    event = 'InsertEnter',
    config = function()
      require('configs.nvim-treesitter-endwise')
    end,
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
      { '<M-C-Up>', desc = 'Join current treesitter node' },
      { '<M-NL>', desc = 'Split current treesitter node' },
      { '<M-C-Down>', desc = 'Split current treesitter node' },
      { 'g<M-NL>', desc = 'Split current treesitter node recursively' },
      { 'g<M-C-Down>', desc = 'Split current treesitter node recursively' },
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
