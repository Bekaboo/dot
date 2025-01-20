---@param buf integer?
local function table_mode_toggle(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  vim.api.nvim_buf_call(buf, function()
    local ft = vim.bo.ft
    local table_mode_buf_is_active = vim.fn['tablemode#IsActive']() == 1
    if ft == 'markdown' and not table_mode_buf_is_active then
      vim.cmd.TableModeEnable({
        mods = {
          silent = true,
          emsg_silent = true,
        },
      })
      return
    end

    if ft ~= 'markdown' and table_mode_buf_is_active then
      vim.cmd.TableModeDisable({
        mods = {
          silent = true,
          emsg_silent = true,
        },
      })
    end
  end)
end

table_mode_toggle()

vim.api.nvim_create_autocmd({ 'Filetype', 'BufEnter' }, {
  group = vim.api.nvim_create_augroup('TableModeAutoToggle', {}),
  callback = function(info)
    table_mode_toggle(info.buf)
  end,
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
