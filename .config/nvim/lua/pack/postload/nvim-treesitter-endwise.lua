-- Manually trigger `FileType` event to make nvim-treesitter-endwise
-- attach to current file when loaded
vim.api.nvim_exec_autocmds('FileType', {})

