return {
  {
    'olimorris/codecompanion.nvim',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-treesitter/nvim-treesitter',
    },
    keys = {
      { '<Leader>+', desc = 'AI inline assistant' },
      { '<Leader>!', desc = 'AI actions' },
      { '<Leader>@', mode = 'n', desc = 'AI chat assistant' },
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
