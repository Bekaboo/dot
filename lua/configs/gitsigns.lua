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
vim.keymap.set({ 'n', 'x' }, ']c', function()
  if vim.wo.diff then
    vim.api.nvim_feedkeys(vim.v.count1 .. ']c', 'n', true)
    return
  end
  for _ = 1, vim.v.count1 do
    gs.next_hunk()
  end
end)

vim.keymap.set({ 'n', 'x' }, '[c', function()
  if vim.wo.diff then
    vim.api.nvim_feedkeys(vim.v.count1 .. '[c', 'n', true)
    return
  end
  for _ = 1, vim.v.count1 do
    gs.prev_hunk()
  end
end)

-- Actions
vim.keymap.set('n', '<leader>gs', gs.stage_hunk)
vim.keymap.set('n', '<leader>gr', gs.reset_hunk)
vim.keymap.set('n', '<leader>gS', gs.stage_buffer)
vim.keymap.set('n', '<leader>gu', gs.undo_stage_hunk)
vim.keymap.set('n', '<leader>gR', gs.reset_buffer)
vim.keymap.set('n', '<leader>gp', gs.preview_hunk)
vim.keymap.set('n', '<leader>gb', gs.blame_line)
vim.keymap.set('n', '<leader>g<esc>', '<nop>')

vim.keymap.set('x', '<leader>gs', function()
  gs.stage_hunk({
    vim.fn.line('.'),
    vim.fn.line('v'),
  })
end)
vim.keymap.set('x', '<leader>gr', function()
  gs.reset_hunk({
    vim.fn.line('.'),
    vim.fn.line('v'),
  })
end)

-- Text object
vim.keymap.set(
  { 'o', 'x' },
  'ic',
  ':<C-U>Gitsigns select_hunk<CR>',
  { silent = true }
)
vim.keymap.set(
  { 'o', 'x' },
  'ac',
  ':<C-U>Gitsigns select_hunk<CR>',
  { silent = true }
)
