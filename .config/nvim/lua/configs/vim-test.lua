-- stylua: ignore start
vim.keymap.set('n', '<Leader>tk', '<Cmd>TestClass<CR>',   { desc = 'Run the first test class in current file' })
vim.keymap.set('n', '<Leader>ta', '<Cmd>TestFile<CR>',    { desc = 'Run all tests in current file' })
vim.keymap.set('n', '<Leader>tt', '<Cmd>TestNearest<CR>', { desc = 'Run the test neartest to cursor' })
vim.keymap.set('n', '<Leader>t$', '<Cmd>TestLast<CR>',    { desc = 'Run the last test' })
vim.keymap.set('n', '<Leader>ts', '<Cmd>TestSuite<CR>',   { desc = 'Run the whole test suite' })
vim.keymap.set('n', '<Leader>to', '<Cmd>TestVisit<CR>',   { desc = 'Go to last visited test file' })
-- stylua: ignore off
