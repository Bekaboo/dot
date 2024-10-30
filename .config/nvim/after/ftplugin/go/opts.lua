-- Go enforces tabs for indentation
vim.bo.expandtab = false
vim.bo.shiftwidth = 0
vim.bo.softtabstop = 0

-- Set 'formatoptions' to align with the behavior in other languages
vim.opt_local.formatoptions:remove('t')
vim.opt_local.formatoptions:append('croql')
