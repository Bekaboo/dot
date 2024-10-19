return {
  {
    'karb94/neoscroll.nvim',
    event = {
      'BufNew',
      'BufReadPre',
      'BufWritePost',
      'TextChanged',
      'TextChangedI',
      'StdinReadPre',
    },
    config = function()
      require('configs.neoscroll')
    end,
  },
}
