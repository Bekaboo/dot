return {
  {
    src = 'https://github.com/nvim-treesitter/nvim-treesitter',
    version = 'main', -- master branch is deprecated
    data = {
      build = function()
        local ts_install_ok, ts_install =
          pcall(require, 'nvim-treesitter.install')
        if ts_install_ok then
          ts_install.update()
        end
      end,
      cmds = {
        'TSInstall',
        'TSInstallFromGrammar',
        'TSUninstall',
        'TSUpdate',
      },
      -- Skip loading nvim-treesitter for plugin-specific filetypes containing
      -- underscores (e.g. 'cmp_menu') to improve initial cmdline responsiveness
      -- on slower systems
      events = { event = 'FileType', pattern = '[^_]\\+' },
    },
  },

  {
    src = 'https://github.com/nvim-treesitter/nvim-treesitter-textobjects',
    -- 'main' branch uses `vim.treesitter` module and does not depend on
    -- nvim-treesitter, compatible with nvim-treesitter 'master' -> 'main'
    -- switch
    version = 'main',
    data = {
      events = { event = 'FileType', pattern = '[^_]\\+' },
    },
  },

  {
    src = 'https://github.com/RRethy/nvim-treesitter-endwise',
    data = {
      events = 'InsertEnter',
    },
  },

  {
    src = 'https://github.com/tronikelis/ts-autotag.nvim',
    data = {
      events = 'InsertEnter',
    },
  },

  {
    src = 'https://github.com/Wansmer/treesj',
    data = {
      cmds = { 'TSJToggle', 'TSJSplit', 'TSJJoin' },
      keys = {
        { lhs = '<M-C-K>', desc = 'Join current treesitter node' },
        { lhs = '<M-C-Up>', desc = 'Join current treesitter node' },
        { lhs = '<M-NL>', desc = 'Split current treesitter node' },
        { lhs = '<M-C-Down>', desc = 'Split current treesitter node' },
        {
          lhs = 'g<M-NL>',
          desc = 'Split current treesitter node recursively',
        },
        {
          lhs = 'g<M-C-Down>',
          desc = 'Split current treesitter node recursively',
        },
      },
    },
  },

  {
    src = 'https://github.com/Eandrju/cellular-automaton.nvim',
    data = {
      cmds = 'CellularAutomaton',
    },
  },
}
