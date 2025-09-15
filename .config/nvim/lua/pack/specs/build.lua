return {
  {
    src = 'https://github.com/tpope/vim-projectionist',
    data = {
      events = 'BufReadPre',
    },
  },

  {
    src = 'https://github.com/tpope/vim-dispatch',
    data = {
      cmds = { 'Dispatch', 'Start', 'Focus', 'Make' },
    },
  },

  {
    src = 'https://github.com/vim-test/vim-test',
    data = {
      deps = 'https://github.com/tpope/vim-dispatch',
      keys = {
        {
          lhs = '<Leader>tk',
          desc = 'Run the first test class in current file',
        },
        { lhs = '<Leader>tf', desc = 'Run all tests in current file' },
        { lhs = '<Leader>tt', desc = 'Run the test neartest to cursor' },
        { lhs = '<Leader>tr', desc = 'Run the last test' },
        { lhs = '<Leader>ts', desc = 'Run the whole test suite' },
        { lhs = '<Leader>to', desc = 'Go to last visited test file' },
      },
      cmds = {
        'TestClass',
        'TestVisit',
        'TestNearest',
        'TestSuite',
        'TestFile',
        'TestLast',
      },
    },
  },
}
