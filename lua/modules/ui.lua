return {
  {
    'karb94/neoscroll.nvim',
    lazy = true,
    init = function()
      vim.api.nvim_create_autocmd('UIEnter', {
        desc = 'Lazy-load neoscroll after UIEnter.',
        once = true,
        callback = vim.schedule_wrap(function()
          require('neoscroll')
        end),
      })
    end,
    config = function()
      require('configs.neoscroll')
    end,
  },
}
