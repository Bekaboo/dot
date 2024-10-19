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

---Set additional scrolling keymaps for helpfiles
---@param buf integer
---@return nil
local function map_scroll_helpfiles(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local ft = vim.bo[buf].ft
  if ft ~= 'man' and ft ~= 'help' then
    return
  end

  vim.keymap.set({ 'n', 'x' }, 'd', function()
    if vim.v.count ~= 0 then
      vim.opt_local.scr = math.min(vim.api.nvim_win_get_height(0), vim.v.count)
    end
    nsc.scroll(vim.wo.scr, {
      move_cursor = true,
      duration = scroll_duration(),
    })
  end, { buffer = buf, nowait = true })
  vim.keymap.set({ 'n', 'x' }, 'u', function()
    if vim.v.count ~= 0 then
      vim.opt_local.scr = math.min(vim.api.nvim_win_get_height(0), vim.v.count)
    end
    nsc.scroll(-vim.wo.scr, {
      move_cursor = true,
      duration = scroll_duration(),
    })
  end, { buffer = buf, nowait = true })
end

for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  map_scroll_helpfiles(buf)
end

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('NeoscrollSetUp', {}),
  pattern = { 'help', 'man' },
  callback = function(info)
    map_scroll_helpfiles(info.buf)
  end,
})
