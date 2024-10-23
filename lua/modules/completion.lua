return {
  {
    'hrsh7th/nvim-cmp',
    lazy = true,
    config = function()
      require('configs.nvim-cmp')
    end,
    dependencies = 'L3MON4D3/LuaSnip',
  },

  {
    'hrsh7th/cmp-calc',
    event = 'InsertEnter',
    dependencies = 'hrsh7th/nvim-cmp',
  },

  {
    'hrsh7th/cmp-cmdline',
    event = 'CmdlineEnter',
    dependencies = 'hrsh7th/nvim-cmp',
  },

  {
    'hrsh7th/cmp-nvim-lsp',
    event = 'InsertEnter',
    dependencies = 'hrsh7th/nvim-cmp',
  },

  {
    'hrsh7th/cmp-nvim-lsp-signature-help',
    event = 'InsertEnter',
    dependencies = 'hrsh7th/nvim-cmp',
  },

  {
    'hrsh7th/cmp-buffer',
    event = { 'CmdlineEnter', 'InsertEnter' },
    dependencies = 'hrsh7th/nvim-cmp',
  },

  {
    'rcarriga/cmp-dap',
    lazy = true,
    dependencies = {
      'mfussenegger/nvim-dap',
      'hrsh7th/nvim-cmp',
    },
  },

  {
    'saadparwaiz1/cmp_luasnip',
    event = 'InsertEnter',
    dependencies = {
      'hrsh7th/nvim-cmp',
      'L3MON4D3/LuaSnip',
    },
  },

  {
    'hrsh7th/cmp-path',
    event = { 'InsertEnter', 'CmdlineEnter' },
    dependencies = 'hrsh7th/nvim-cmp',
  },

  {
    'L3MON4D3/LuaSnip',
    build = 'make install_jsregexp',
    event = 'ModeChanged *:[iRss\x13vV\x16]*',
    config = function()
      require('configs.LuaSnip')
    end,
  },
}
