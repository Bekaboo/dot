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
      { '<Leader>+', desc = 'Inline AI help' },
      { '<Leader><Leader>@', desc = 'Pick AI actions' },
      { '<Leader>@', mode = 'n', desc = 'Chat with AI' },
      { '<Leader>@', mode = 'x', desc = 'Add selection to conversation with AI' },
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
