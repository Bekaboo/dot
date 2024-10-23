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
    'olimorris/codecompanion.nvim',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-treesitter/nvim-treesitter',
    },
    keys = {
      { '<Leader><Leader>@' },
      { '<Leader>@', mode = { 'n', 'x' } },
    },
    commands = {
      'CodeCompanion',
      'CodeCompanionActions',
      'CodeCompanionChat',
    },
    config = function()
      require('configs.codecompanion')
    end,
  },
}
