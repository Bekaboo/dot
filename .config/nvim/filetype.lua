vim.api.nvim_create_autocmd('BufReadPre', {
  once = true,
  callback = function()
    vim.filetype.add({
      extension = {
        -- Special filetypes for Weixin Mini Program
        wxss = 'css',
        wxml = 'html',
      },
    })
    return true
  end,
})
