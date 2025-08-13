return {
  {
    'tpope/vim-projectionist',
    event = 'BufReadPre',
    config = function()
      require('configs.vim-projectionist')
    end,
  },

  {
    'tpope/vim-dispatch',
    cmd = { 'Dispatch', 'Start', 'Focus', 'Make' },
    config = function()
      require('configs.vim-dispatch')
    end,
  },

  {
    'vim-test/vim-test',
    dependencies = 'vim-dispatch',
    keys = {
      { '<Leader>tk', desc = 'Run the first test class in current file' },
      { '<Leader>tf', desc = 'Run all tests in current file' },
      { '<Leader>tt', desc = 'Run the test neartest to cursor' },
      { '<Leader>tr', desc = 'Run the last test' },
      { '<Leader>ts', desc = 'Run the whole test suite' },
      { '<Leader>to', desc = 'Go to last visited test file' },
    },
    cmd = {
      'TestClass',
      'TestVisit',
      'TestNearest',
      'TestSuite',
      'TestFile',
      'TestLast',
    },
    config = function()
      require('configs.vim-test')
    end,
  },
}
