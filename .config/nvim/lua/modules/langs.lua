return {
  {
    'p00f/clangd_extensions.nvim',
    ft = { 'c', 'cpp' },
    config = function()
      require('configs.clangd_extensions')
    end,
  },
}
