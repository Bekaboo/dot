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
      'TSInstallFromGrammar',
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
    -- Skip loading nvim-treesitter for plugin-specific filetypes containing
    -- underscores (e.g. 'cmp_menu') to improve initial cmdline responsiveness
    -- on slower systems
    event = 'FileType [^_]\\+',
    config = function()
      require('configs.nvim-treesitter')
    end,
  },

  {
    'nvim-treesitter/nvim-treesitter-textobjects',
    dependencies = 'nvim-treesitter/nvim-treesitter',
    event = 'FileType [^_]\\+',
    config = function()
      require('configs.nvim-treesitter-textobjects')
    end,
  },

  {
    'RRethy/nvim-treesitter-endwise',
    dependencies = 'nvim-treesitter/nvim-treesitter',
    event = 'InsertEnter',
    config = function()
      -- Manually trigger `FileType` event to make nvim-treesitter-endwise
      -- attach to current file when loaded
      vim.api.nvim_exec_autocmds('FileType', {})
    end,
  },

  {
    'tronikelis/ts-autotag.nvim',
    event = 'InsertEnter',
    dependencies = 'nvim-treesitter/nvim-treesitter',
    config = true,
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
