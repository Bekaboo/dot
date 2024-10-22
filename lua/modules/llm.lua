return {
  {
    'Exafunction/codeium.vim',
    event = 'InsertEnter',
    commands = {
      'Codeium',
      'CodeiumAuto',
      'CodeiumChat',
      'CodeiumEnable',
      'CodeiumManual',
      'CodeiumToggle',
    },
    config = function()
      require('configs.codeium')
    end,
  },

  {
    'yetone/avante.nvim',
    build = 'make',
    event = {
      'BufNew',
      'BufReadPre',
      'BufWritePost',
      'FileType',
      'ModeChanged',
      'StdinReadPre',
    },
    keys = {
      '<Leader>@',
      { '<Leader>.', mode = { 'x' } },
    },
    commands = {
      'AvanteAsk',
      'AvanteFocus',
      'AvanteSwitchProvider',
      'AvanteEdit',
      'AvanteChat',
      'AvanteBuild',
      'AvanteToggle',
    },
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
      'nvim-tree/nvim-web-devicons',
      'nvim-lua/plenary.nvim',
      'MunifTanjim/nui.nvim',
    },
    config = function()
      require('configs.avante')
    end,
  },
}
