if vim.fn.win_gettype() ~= 'command' then
  return
end

vim.bo.buflisted = false
vim.opt_local.wrap = true
vim.opt_local.rnu = false
vim.opt_local.signcolumn = 'no'
vim.opt_local.statuscolumn = ''
