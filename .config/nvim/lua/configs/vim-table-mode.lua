---@param buf integer?
local function table_mode_toggle(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local ft = vim.bo[buf].ft
  local cmd = (ft == 'markdown' or ft == 'text') and 'TableModeEnable'
    or 'TableModeDisable'
  vim.cmd[cmd]({
    mods = {
      silent = true,
      emsg_silent = true,
    },
  })
end

table_mode_toggle()

vim.api.nvim_create_autocmd({ 'Filetype', 'BufEnter' }, {
  group = vim.api.nvim_create_augroup('TableModeAutoToggle', {}),
  callback = function(info)
    table_mode_toggle(info.buf)
  end,
})

vim.api.nvim_create_autocmd('Filetype', {
  pattern = 'markdown',
  group = vim.api.nvim_create_augroup('TableModeSetTableCorner', {}),
  command = 'let b:table_mode_corner = "|"',
})

vim.api.nvim_create_autocmd('BufWritePre', {
  group = vim.api.nvim_create_augroup('TableModeFormatOnSave', {}),
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
