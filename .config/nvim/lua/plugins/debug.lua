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
      { '<Leader>Gg', desc = 'Continue program execution' },
      { '<Leader>GG', desc = 'Continue program execution' },
      { '<Leader>Ge', desc = 'Open debug REPL' },
      { '<Leader>Gb', desc = 'Toggle breakpoint' },
      { '<Leader>GB', desc = 'Set conditional breakpoint' },
      { '<Leader>Gl', desc = 'Set logpoint' },
    },
    dependencies = 'igorlfs/nvim-dap-view',
    config = function()
      require('configs.nvim-dap')
    end,
  },

  {
    'igorlfs/nvim-dap-view',
    lazy = true,
    config = function()
      require('configs.nvim-dap-view')
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
}
