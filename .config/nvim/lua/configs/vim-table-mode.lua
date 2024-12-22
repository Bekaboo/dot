vim.api.nvim_create_augroup('TableModeSetTableCorner', { clear = true })
vim.api.nvim_create_autocmd('Filetype', {
  pattern = 'markdown',
  group = 'TableModeSetTableCorner',
  command = 'let b:table_mode_corner = "|"',
})

vim.api.nvim_create_augroup('TableModeFormatOnSave', { clear = true })
vim.api.nvim_create_autocmd('BufWritePre', {
  group = 'TableModeFormatOnSave',
  callback = function(info)
    if
      vim.bo[info.buf].ft == 'markdown'
      and vim.api.nvim_get_current_line():match('^%s*|')
    then
      vim.cmd.TableModeRealign({
        mods = { emsg_silent = true },
      })
    end
  end,
})
