return {
  {
    'hrsh7th/nvim-cmp',
    lazy = true,
    config = function()
      require('configs.nvim-cmp')
    end,
    dependencies = 'LuaSnip',
  },

  {
    'hrsh7th/cmp-calc',
    event = 'InsertEnter',
    dependencies = 'nvim-cmp',
  },

  {
    'hrsh7th/cmp-cmdline',
    event = 'CmdlineEnter',
    dependencies = 'nvim-cmp',
  },

  {
    'hrsh7th/cmp-nvim-lsp',
    event = 'InsertEnter',
    dependencies = { 'nvim-cmp', 'nvim-lspconfig' },
  },

  {
    'hrsh7th/cmp-nvim-lsp-signature-help',
    event = 'InsertEnter',
    dependencies = { 'nvim-cmp', 'nvim-lspconfig' },
  },

  {
    'tzachar/fuzzy.nvim',
    lazy = true,
  },

  {
    'tzachar/cmp-fuzzy-path',
    event = { 'CmdlineEnter', 'InsertEnter' },
    dependencies = { 'fuzzy.nvim', 'nvim-cmp' },
  },

  {
    'tzachar/cmp-fuzzy-buffer',
    event = { 'CmdlineEnter', 'InsertEnter' },
    dependencies = { 'fuzzy.nvim', 'nvim-cmp' },
  },

  {
    'rcarriga/cmp-dap',
    lazy = true,
    dependencies = { 'nvim-dap', 'nvim-cmp' },
  },

  {
    'saadparwaiz1/cmp_luasnip',
    event = 'InsertEnter',
    dependencies = { 'nvim-cmp', 'LuaSnip' },
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
    event = 'InsertEnter',
    config = function()
      require('configs.LuaSnip')
    end,
  },
}
