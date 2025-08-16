-- Disable validation for speed
---@diagnostic disable-next-line: duplicate-set-field
vim.validate = function() end

-- Enable faster lua loader using byte-compilation
-- https://github.com/neovim/neovim/commit/2257ade3dc2daab5ee12d27807c0b3bcf103cd29
vim.loader.enable()

require('core.opts')
require('core.keymaps')
require('core.autocmds')
require('core.plugins')

vim.api.nvim_create_autocmd('FileType', {
  once = true,
  desc = 'Apply treesitter settings.',
  callback = function()
    require('core.treesitter')
  end,
})

vim.api.nvim_create_autocmd({ 'FileType', 'LspAttach' }, {
  once = true,
  desc = 'Apply lsp settings.',
  callback = function()
    require('core.lsp')
  end,
})

vim.api.nvim_create_autocmd('DiagnosticChanged', {
  once = true,
  desc = 'Apply diagnostic settings.',
  callback = function()
    require('core.diagnostic')
  end,
})
