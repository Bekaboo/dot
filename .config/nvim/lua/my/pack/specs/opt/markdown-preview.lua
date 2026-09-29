---@type my.pack.spec
return {
  src = 'https://github.com/iamcco/markdown-preview.nvim',
  data = {
    build = 'cd app && npm install && cd - && git restore .',
    cmds = {
      'MarkdownPreview',
      'MarkdownPreviewStop',
      'MarkdownPreviewToggle',
    },
    init = function()
      vim.g.mkdp_filetypes = { 'markdown' }
      vim.g.mkdp_auto_close = 0
      vim.g.mkdp_theme = 'light'
    end,
    postload = function()
      vim.api.nvim_exec_autocmds('FileType', {
        group = 'mkdp_init',
        buffer = 0,
      })
    end,
  },
}
