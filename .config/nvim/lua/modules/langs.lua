return {
  {
    'p00f/clangd_extensions.nvim',
    ft = { 'c', 'cpp', 'objc', 'objcpp', 'cuda' },
    config = function()
      require('configs.clangd_extensions')
    end,
  },
}
