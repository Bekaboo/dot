return {
  {
    src = 'https://github.com/mfussenegger/nvim-dap',
    data = {
      deps = 'https://github.com/rcarriga/nvim-dap-ui',
      cmds = {
        'DapContinue',
        'DapLoadLaunchJSON',
        'DapRestartFrame',
        'DapSetLogLevel',
        'DapShowLog',
        'DapToggleBreakPoint',
      },
      keys = {
        { lhs = '<F5>', desc = 'Continue program execution' },
        { lhs = '<F8>', desc = 'Open debug REPL' },
        { lhs = '<F9>', desc = 'Toggle breakpoint' },
        { lhs = '<F21>', desc = 'Set conditional breakpoint' },
        { lhs = '<F45>', desc = 'Set logpoint' },
        { lhs = '<Leader>Gc', desc = 'Continue program execution' },
        { lhs = '<Leader>Gg', desc = 'Continue program execution' },
        { lhs = '<Leader>GG', desc = 'Continue program execution' },
        { lhs = '<Leader>Ge', desc = 'Open debug REPL' },
        { lhs = '<Leader>Gb', desc = 'Toggle breakpoint' },
        { lhs = '<Leader>GB', desc = 'Set conditional breakpoint' },
        { lhs = '<Leader>Gl', desc = 'Set logpoint' },
      },
    },
  },

  {
    src = 'https://github.com/jbyuki/one-small-step-for-vimkind',
    data = {
      deps = 'https://github.com/mfussenegger/nvim-dap',
      cmds = 'DapOSVLaunchServer',
    },
  },

  {
    src = 'https://github.com/rcarriga/nvim-dap-ui',
    data = {
      lazy = true,
      deps = {
        'https://github.com/mfussenegger/nvim-dap',
        'https://github.com/nvim-neotest/nvim-nio',
        'https://github.com/kyazdani42/nvim-web-devicons',
      },
    },
  },
}
