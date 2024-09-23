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
    keys = { '<F5>', '<F8>', '<F9>', '<F21>', '<F45>', '<Leader>G' },
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
