return {
  {
    'kyazdani42/nvim-web-devicons',
    lazy = true,
    enabled = vim.g.has_nf,
    config = function()
      require('configs.nvim-web-devicons')
    end,
  },
}
