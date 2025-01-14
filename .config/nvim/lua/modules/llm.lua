return {
  {
    'olimorris/codecompanion.nvim',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-treesitter/nvim-treesitter',
    },
    keys = {
      { '<Leader>+', desc = 'Inline AI help' },
      { '<Leader><Leader>@', desc = 'Pick AI actions' },
      { '<Leader>@', mode = 'n', desc = 'Chat with AI assistant' },
      {
        '<Leader>@',
        mode = 'x',
        desc = 'Add selection to conversation with AI',
      },
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
