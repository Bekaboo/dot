vim.bo.commentstring = '# %s'

-- Set 'formatoptions' to align with the behavior in other languages
vim.opt_local.formatoptions:remove('t')
vim.opt_local.formatoptions:append('croql')
