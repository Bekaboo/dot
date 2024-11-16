return {
  {
    'mfussenegger/nvim-dap',
    cmd = {
      'DapContinue',
      'DapLoadLaunchJSON',
      'DapRestartFrame',
      'DapSetLogLevel',
      'DapShowLog',
      'DapToggleBreakPoint',
    },
    keys = {
      { '<F5>', desc = 'Continue program execution' },
      { '<F8>', desc = 'Open debug REPL' },
      { '<F9>', desc = 'Toggle breakpoint' },
      { '<F21>', desc = 'Set conditional breakpoint' },
      { '<F45>', desc = 'Set logpoint' },
      { '<Leader>Gc', desc = 'Continue program execution' },
      { '<Leader>Ge', desc = 'Open debug REPL' },
      { '<Leader>Gb', desc = 'Toggle breakpoint' },
      { '<Leader>GB', desc = 'Set conditional breakpoint' },
      { '<Leader>Gl', desc = 'Set logpoint' },
    },
    dependencies = {
      'rcarriga/cmp-dap',
      'rcarriga/nvim-dap-ui',
    },
    config = function()
      require('configs.nvim-dap')
    end,
  },

  {
    'jbyuki/one-small-step-for-vimkind',
    cmd = 'DapOSVLaunchServer',
    dependencies = 'mfussenegger/nvim-dap',
    config = function()
      require('configs.one-small-step-for-vimkind')
    end,
  },

  {
    'rcarriga/nvim-dap-ui',
    lazy = true,
    dependencies = {
      'mfussenegger/nvim-dap',
      'nvim-neotest/nvim-nio',
      'kyazdani42/nvim-web-devicons',
    },
    config = function()
      require('configs.nvim-dap-ui')
    end,
  },
}
