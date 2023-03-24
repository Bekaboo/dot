return {
  {
    'williamboman/mason.nvim',
    cmd = {
      'Mason',
      'MasonUninstall',
      'MasonLog',
      'MasonInstall',
      'MasonUninstallAll',
    },
    config = function()
      require('configs.mason')
    end,
  },

  {
    'nvim-telescope/telescope.nvim',
    cmd = 'Telescope',
    keys = {
      '<Leader>F', '<Leader>f', '<Leader>ff', '<Leader>fo',
      '<Leader>f;', '<Leader>f*', '<Leader>fh', '<Leader>fm',
      '<Leader>fb', '<Leader>fr', '<Leader>fa', '<Leader>fe',
      '<Leader>fp', '<Leader>fs', '<Leader>fS', '<Leader>fg',
      '<Leader>fm', '<Leader>fd'
    },
    dependencies = {
      'plenary.nvim',
      'telescope-fzf-native.nvim'
    },
    config = function()
      require('configs.telescope')
    end,
  },

  {
    'nvim-telescope/telescope-fzf-native.nvim',
    -- If it complains 'fzf doesn't exists, run 'make' inside
    -- the root folder of this plugin
    build = 'make',
    lazy = true,
    dependencies = { 'plenary.nvim', 'telescope.nvim' },
  },

  {
    'debugloop/telescope-undo.nvim',
    lazy = true,
    dependencies = { 'plenary.nvim', 'telescope.nvim' },
  },

  {
    'voldikss/vim-floaterm',
    keys = {
      { '<C-\\>', mode = { 'n', 't' } },
      { '<M-i>', mode = { 'n', 't' } },
    },
    cmd = { 'FloatermNew', 'FloatermToggle', 'ToggleTool' },
    config = function()
      require('configs.vim-floaterm')
    end,
  },

  {
    'lewis6991/gitsigns.nvim',
    event = 'BufReadPre',
    dependencies = 'plenary.nvim',
    config = function()
      require('configs.gitsigns')
    end,
  },

  {
    'kevinhwang91/rnvimr',
    cond = function()
      if vim.fn.executable('ranger') == 1 then
        vim.g.loaded_netrw = 1
        vim.g.loaded_netrwPlugin = 1
        vim.g.loaded_netrwSettings = 1
        return true
      end
      return false
    end,
    config = function()
      require('configs.rnvimr')
    end,
  },

  {
    'aserowy/tmux.nvim',
    keys = { '<M-h>', '<M-j>', '<M-k>', '<M-l>' },
    config = function()
      require('configs.tmux')
    end,
  },

  {
    'NvChad/nvim-colorizer.lua',
    event = { 'BufNew', 'BufRead' },
    config = function()
      require('configs.nvim-colorizer')
    end,
  },
}
