return {
  src = 'https://github.com/iamcco/markdown-preview.nvim',
  data = {
    build = 'cd app && npm install && cd - && git restore .',
    events = {
      event = 'Filetype',
      pattern = 'markdown',
    },
    postload = function()
      vim.g.mkdp_filetypes = { 'markdown' }
      vim.g.mkdp_auto_close = 0
      vim.g.mkdp_theme = 'light'
    end,
  },
}
