local icons = require('utils').static.icons
local gs = require('gitsigns')

gs.setup({
  preview_config = {
    border = 'solid',
    style = 'minimal',
  },
  signs = {
    add = { text = vim.trim(icons.GitSignAdd) },
    untracked = { text = vim.trim(icons.GitSignUntracked) },
    change = { text = vim.trim(icons.GitSignChange) },
    delete = { text = vim.trim(icons.GitSignDelete) },
    topdelete = { text = vim.trim(icons.GitSignTopdelete) },
    changedelete = { text = vim.trim(icons.GitSignChangedelete) },
  },
  signs_staged_enable = false,
  current_line_blame = false,
  current_line_blame_opts = {
    virt_text = true,
    virt_text_pos = 'eol',
    delay = 100,
  },
})

-- Setup keymaps
-- Navigation
-- stylua: ignore start
vim.keymap.set({ 'n', 'x' }, '[c', function() gs.nav_hunk('prev') end, { desc = 'Go to previous git hunk' })
vim.keymap.set({ 'n', 'x' }, ']c', function() gs.nav_hunk('next') end, { desc = 'Go to next git hunk' })
vim.keymap.set({ 'n', 'x' }, '[C', function() gs.nav_hunk('first') end, { desc = 'Go to first git hunk' })
vim.keymap.set({ 'n', 'x' }, ']C', function() gs.nav_hunk('last') end, { desc = 'Go to last git hunk' })
-- stylua: ignore end

-- Actions
-- stylua: ignore start
vim.keymap.set('n', '<leader>gs', gs.stage_hunk, { desc = 'Git stage current hunk' })
vim.keymap.set('n', '<leader>gr', gs.reset_hunk, { desc = 'Git reset current hunk' })
vim.keymap.set('n', '<leader>gS', gs.stage_buffer, { desc = 'Git stage current buffer' })
vim.keymap.set('n', '<leader>gu', gs.undo_stage_hunk, { desc = 'Git unstage current hunk' })
vim.keymap.set('n', '<leader>gR', gs.reset_buffer, { desc = 'Git reset current buffer' })
vim.keymap.set('n', '<leader>gp', gs.preview_hunk, { desc = 'Git preview current hunk' })
vim.keymap.set('n', '<leader>gb', gs.blame_line, { desc = 'Git blame current line' })
vim.keymap.set('n', '<leader>g<esc>', '<nop>')
-- stylua: ignore end

vim.keymap.set('x', '<leader>gs', function()
  gs.stage_hunk({
    vim.fn.line('.'),
    vim.fn.line('v'),
  })
end, { desc = 'Git stage current hunk' })
vim.keymap.set('x', '<leader>gr', function()
  gs.reset_hunk({
    vim.fn.line('.'),
    vim.fn.line('v'),
  })
end, { desc = 'Git reset current hunk' })

-- Text object
-- stylua: ignore start
vim.keymap.set({ 'o', 'x' }, 'ic', ':<C-U>Gitsigns select_hunk<CR>', { silent = true, desc = 'Select git hunk' })
vim.keymap.set({ 'o', 'x' }, 'ac', ':<C-U>Gitsigns select_hunk<CR>', { silent = true, desc = 'Select git hunk' })
-- stylua: ignore end
