return {
  {
    'Exafunction/codeium.vim',
    -- Not supported under termux:
    -- http://github.com/Exafunction/codeium/issues/33
    enabled = not vim.env.TERMUX_VERSION,
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
