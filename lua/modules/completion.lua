return {
  {
    'yioneko/nvim-cmp',
    branch = 'perf',
    lazy = true,
    config = function()
      require('configs.nvim-cmp')
    end,
    dependencies = 'L3MON4D3/LuaSnip',
  },

  {
    'hrsh7th/cmp-calc',
    event = 'InsertEnter',
    dependencies = 'yioneko/nvim-cmp',
  },

  {
    'hrsh7th/cmp-cmdline',
    event = 'CmdlineEnter',
    dependencies = 'yioneko/nvim-cmp',
  },

  {
    'hrsh7th/cmp-nvim-lsp',
    event = 'InsertEnter',
    dependencies = 'yioneko/nvim-cmp',
  },

  {
    'hrsh7th/cmp-nvim-lsp-signature-help',
    event = 'InsertEnter',
    dependencies = 'yioneko/nvim-cmp',
  },

  {
    'hrsh7th/cmp-buffer',
    event = { 'CmdlineEnter', 'InsertEnter' },
    dependencies = 'yioneko/nvim-cmp',
  },

  {
    'rcarriga/cmp-dap',
    lazy = true,
    dependencies = {
      'mfussenegger/nvim-dap',
      'yioneko/nvim-cmp',
    },
  },

  {
    'saadparwaiz1/cmp_luasnip',
    event = 'InsertEnter',
    dependencies = {
      'yioneko/nvim-cmp',
      'L3MON4D3/LuaSnip',
    },
  },

  {
    'hrsh7th/cmp-path',
    event = { 'InsertEnter', 'CmdlineEnter' },
    dependencies = 'yioneko/nvim-cmp',
  },

  {
    'zbirenbaum/copilot.lua',
    cmd = 'Copilot',
    event = 'InsertEnter',
    config = function()
      require('configs.copilot')
    end,
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
