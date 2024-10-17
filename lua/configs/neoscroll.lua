local nsc = require('neoscroll')

nsc.setup({
  easing = 'quadratic',
  hide_cursor = false,
  mappings = {},
})

---Return scroll duration for the current window
---@return integer
local function scroll_duration()
  return math.min(90, 3 * vim.api.nvim_win_get_height(0))
end

-- stylua: ignore start
vim.keymap.set({ 'n', 'x' }, '<C-e>', function() nsc.scroll(vim.v.count1, { move_cursor = false, duration = scroll_duration() }) end)
vim.keymap.set({ 'n', 'x' }, '<C-y>', function() nsc.scroll(-vim.v.count1, { move_cursor = false, duration = scroll_duration() }) end)
vim.keymap.set({ 'n', 'x' }, '<C-d>', function() if vim.v.count ~= 0 then vim.opt_local.scr = math.min(vim.api.nvim_win_get_height(0), vim.v.count) end nsc.scroll((vim.wo.scr), { move_cursor = true, duration = scroll_duration() }) end)
vim.keymap.set({ 'n', 'x' }, '<C-u>', function() if vim.v.count ~= 0 then vim.opt_local.scr = math.min(vim.api.nvim_win_get_height(0), vim.v.count) end nsc.scroll(-(vim.wo.scr), { move_cursor = true, duration = scroll_duration() }) end)
vim.keymap.set({ 'n', 'x' }, '<C-f>', function() nsc.scroll(vim.v.count1 * vim.api.nvim_win_get_height(0), { move_cursor = true, duration = scroll_duration() }) end)
vim.keymap.set({ 'n', 'x' }, '<C-b>', function() nsc.scroll(vim.v.count1 * -vim.api.nvim_win_get_height(0), { move_cursor = true, duration = scroll_duration() }) end)
vim.keymap.set({ 'n', 'x' }, '<S-Up>', function() nsc.scroll(vim.v.count1 * -vim.api.nvim_win_get_height(0), { move_cursor = true, duration = scroll_duration() }) end)
vim.keymap.set({ 'n', 'x' }, '<S-Down>', function() nsc.scroll(vim.v.count1 * vim.api.nvim_win_get_height(0), { move_cursor = true, duration = scroll_duration() }) end)
vim.keymap.set({ 'n', 'x' }, '<PageUp>', function() nsc.scroll(vim.v.count1 * -vim.api.nvim_win_get_height(0), { move_cursor = true, duration = scroll_duration() }) end)
vim.keymap.set({ 'n', 'x' }, '<PageDown>', function() nsc.scroll(vim.v.count1 * vim.api.nvim_win_get_height(0), { move_cursor = true, duration = scroll_duration() }) end)
vim.keymap.set({ 'n', 'x' }, '<S-PageUp>', function() nsc.scroll(vim.v.count1 * -vim.api.nvim_win_get_height(0), { move_cursor = true, duration = scroll_duration() }) end)
vim.keymap.set({ 'n', 'x' }, '<S-PageDown>', function() nsc.scroll(vim.v.count1 * vim.api.nvim_win_get_height(0), { move_cursor = true, duration = scroll_duration() }) end)
vim.keymap.set({ 'n', 'x' }, 'zt', function() nsc.zt({ half_win_duration = 40 }) end)
vim.keymap.set({ 'n', 'x' }, 'zz', function() nsc.zz({ half_win_duration = 40 }) end)
vim.keymap.set({ 'n', 'x' }, 'zb', function() nsc.zb({ half_win_duration = 40 }) end)
-- stylua: ignore end
