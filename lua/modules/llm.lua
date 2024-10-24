return {
  {
    'Exafunction/codeium.vim',
    event = 'InsertEnter',
    cmd = {
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
      { '<Leader>+' },
      { '<Leader><Leader>@' },
      { '<Leader>@', mode = { 'n', 'x' } },
    },
    cmd = {
      'CodeCompanion',
      'CodeCompanionActions',
      'CodeCompanionChat',
    },
    config = function()
      require('configs.codecompanion')
    end,
  },
}
