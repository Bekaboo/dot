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

local load = require('utils.load')

load.on_events('FileType', function()
  require('core.treesitter')
end)

load.on_events({ 'FileType', 'LspAttach' }, function()
  return require('core.lsp')
end)

load.on_events('DiagnosticChanged', function()
  require('core.diagnostic')
end)
