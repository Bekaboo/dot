local ls = require('luasnip')
local ls_types = require('luasnip.util.types')
local ls_ft = require('luasnip.extras.filetype_functions')
local utils = require('utils')

---Load snippets for a given filetype
---@param ft string?
local function load_snippets(ft)
  ft = ft or vim.bo.ft

  utils.ft.load_once('snippets', ft, function(_, snips)
    if not snips or vim.tbl_isempty(snips) then
      return false
    end
    for _, group in pairs(snips) do
      ls.add_snippets(ft, group.snip or group, group.opts or {})
    end
    return true
  end)
end

ls.setup({
  ft_func = function()
    load_snippets('all')
    local langs = ls_ft.from_pos_or_filetype()
    for _, lang in ipairs(langs) do
      load_snippets(lang)
    end
    return langs
  end,
  keep_roots = true,
  link_roots = true,
  exit_roots = false,
  link_children = true,
  region_check_events = 'CursorMoved,CursorMovedI,InsertEnter',
  delete_check_events = 'TextChanged,TextChangedI,InsertLeave',
  enable_autosnippets = true,
  cut_selection_keys = '<Tab>',
  ext_opts = {
    [ls_types.choiceNode] = {
      active = {
        virt_text = {
          {
            utils.static.icons.ArrowUpDown,
            'Number',
          },
        },
      },
    },
  },
})

-- Unlink current snippet on leaving insert/select mode
-- https://github.com/L3MON4D3/LuaSnip/issues/258#issuecomment-1011938524
vim.api.nvim_create_autocmd('ModeChanged', {
  desc = 'Unlink current snippet on leaving insert/selection mode.',
  group = vim.api.nvim_create_augroup('LuaSnipModeChanged', {}),
  pattern = '[si]*:[^si]*',
  -- Blink.cmp will enter normal mode shortly on accepting snippet completion,
  -- see https://github.com/Saghen/blink.cmp/issues/2035
  -- We don't want to unlink the current snippet in that case, as a workaround
  -- wait a short time after leaving insert/select mode and unlink current
  -- snippet if still not inside insert/select mode
  callback = vim.schedule_wrap(function(args)
    if vim.fn.mode():match('^[si]') then -- still in insert/select mode
      return
    end
    if ls.session.current_nodes[args.buf] and not ls.session.jump_active then
      ls.unlink_current()
    end
  end),
})

-- Tabout structure, use plugin.tabout if available,
-- fallback to empty functions
local tabout = setmetatable({}, {
  __index = function(self, key)
    if rawget(self, '_init') then
      return
    end
    rawset(self, '_init', true)

    local has_tabout, tabout_plugin = pcall(require, 'plugin.tabout')
    if has_tabout then
      for k, v in pairs(tabout_plugin) do
        self[k] = v
      end
    else
      -- Fallback to empty functions
      self.setup = function() end
      self.jump = function() end
      self.get_jump_pos = function() end
    end
    return rawget(self, key)
  end,
})

---Choose the closer destination between two destinations
---@param dest1 number[]?
---@param dest2 number[]?
---@return number[]|nil
local function choose_closer(dest1, dest2)
  if not dest1 then
    return dest2
  end
  if not dest2 then
    return dest1
  end

  local current_pos = vim.api.nvim_win_get_cursor(0)
  local line_width = vim.api.nvim_win_get_width(0)
  local dist1 = math.abs(dest1[2] - current_pos[2])
    + math.abs(dest1[1] - current_pos[1]) * line_width
  local dist2 = math.abs(dest2[2] - current_pos[2])
    + math.abs(dest2[1] - current_pos[1]) * line_width
  if dist1 <= dist2 then
    return dest1
  else
    return dest2
  end
end

---Jump to the closer destination between a snippet and tabout
---@param snip_dest number[]?
---@param tabout_dest number[]?
---@param direction number 1 or -1
---@return boolean true if a jump is performed
local function jump_to_closer(snip_dest, tabout_dest, direction)
  direction = direction or 1
  local dest = choose_closer(snip_dest, tabout_dest)
  if not dest then
    return false
  end
  -- Prefer snippet jump to break ties
  if vim.deep_equal(dest, snip_dest) then
    ls.jump(direction)
  else
    tabout.jump(direction)
  end
  return true
end

---Convert a range into lsp format range
---@param range integer[][] 0-based range
---@return lsp_range_t
local function range_convert(range)
  local s = range[1]
  local e = range[2]
  return {
    start = { line = s[1], character = s[2] },
    ['end'] = { line = e[1], character = e[2] },
  }
end

---Check if range1 contains range2
---@param range1 integer[][] 0-based range
---@param range2 integer[][] 0-based range
---@return boolean
local function range_contains(range1, range2)
  return require('utils.lsp').range_contains(
    range_convert(range1),
    range_convert(range2)
  )
end

---Check if the cursor position is in the given range
---@param range integer[][] 0-based range
---@param cursor integer[]? 1,0-based cursor position
---@return boolean
local function range_contains_cursor(range, cursor)
  return require('utils.lsp').range_contains_cursor(
    range_convert(range),
    cursor
  )
end

---Find the parent (a previous node that contains the current node) of the node
---@param node table current node
---@return table|nil
local function snip_node_find_parent(node)
  local range_start, range_end = node:get_buf_position()
  local prev = node.parent.snippet and node.parent.snippet.prev.prev
  while prev do
    local range_start_prev, range_end_prev = prev:get_buf_position()
    if
      range_contains(
        { range_start_prev, range_end_prev },
        { range_start, range_end }
      )
    then
      return prev
    end
    prev = prev.parent.snippet and prev.parent.snippet.prev.prev
  end
end

---Check if a node has length larger than 0
---@param node table
---@return boolean
local function snip_node_has_length(node)
  local start_pos, end_pos = node:get_buf_position()
  return start_pos[1] ~= end_pos[1] or start_pos[2] ~= end_pos[2]
end

---Expand current snippet if expandable or jump backward to next snippet
---jump point or tab-out parenthesis
---@param fallback function
local function expand_or_jump(fallback)
  if ls.expandable() then
    ls.expand()
    return
  end

  if not ls.jumpable(1) then
    fallback()
    return
  end

  local tabout_dest = tabout.get_jump_pos(1)
  local snip_range = (function()
    local buf = vim.api.nvim_get_current_buf()
    local node = ls.session
      and ls.session.current_nodes
      and ls.session.current_nodes[buf]
    if not node then
      return
    end
    local parent = snip_node_find_parent(node)
    return snip_node_has_length(node) and { node:get_buf_position() }
      or parent and { parent:get_buf_position() }
  end)()

  -- Don't tabout if it jumps out current snippet range
  if
    not tabout_dest
    or not snip_range
    or not range_contains_cursor(snip_range, tabout_dest)
  then
    ls.jump(1)
    return
  end

  -- If tabout destination is inside current snippet node, use `tabout.jump()`
  -- to jump inside current node without leaving it
  -- We can use `snip.jump()` once we reach the boundary of current
  -- snippet node
  -- |<------ current node range ----->|
  -- |.... ) .... ] ............ } ....|
  --        1      2              3      (tabout jump positions)
  local snip_dest = (function()
    local dest = ls.jump_destination(1):get_buf_position()
    return { dest[1] + 1, dest[2] } -- convert to (1,0) index
  end)()

  -- Jump to tabout or snippet destination depending on their distance
  -- from cursor, prefer snippet jump to break ties
  jump_to_closer(snip_dest, tabout_dest, 1)
end

---Expand current snippet if expandable or jump backward to previous snippet
---jump point or tab-in parenthesis
---@param fallback function
local function expand_or_jump_back(fallback)
  if not ls.jumpable(-1) then
    fallback()
    return
  end

  local tabout_dest = tabout.get_jump_pos(-1)
  local snip_dest = (function()
    local prev = ls.jump_destination(-1)
    if not prev then
      return
    end
    local _, dest = prev:get_buf_position()
    dest[1] = dest[1] + 1 -- (1, 0) indexed
    return dest
  end)()
  if not jump_to_closer(snip_dest, tabout_dest, -1) then
    fallback()
  end
end

---Select previous snippet choice or fallback
---@param fallback function
local function prev_choice(fallback)
  if not ls.choice_active() then
    fallback()
    return
  end
  ls.change_choice(-1)
end

---Select next snippet choice or fallback
---@param fallback function
local function next_choice(fallback)
  if not ls.choice_active() then
    fallback()
    return
  end
  ls.change_choice(1)
end

-- stylua: ignore start
-- Schedule to make sure that the keymaps are amended on top of the
-- `<Tab>`/`<S-Tab>` keymaps defined by tabout plugin: `lua/plugin/tabout.lua`
vim.schedule(function()
  utils.key.amend('i', '<Tab>',   expand_or_jump,      { desc = 'Expand snippet or jump'         })
  utils.key.amend('i', '<S-Tab>', expand_or_jump_back, { desc = 'Expand or jump backward'        })
  utils.key.amend('i', '<C-p>',   prev_choice,         { desc = 'Select previous snippet choice' })
  utils.key.amend('i', '<C-n>',   next_choice,         { desc = 'Select next snippet choice'     })
  utils.key.amend('i', '<Up>',    prev_choice,         { desc = 'Select previous snippet choice' })
  utils.key.amend('i', '<Down>',  next_choice,         { desc = 'Select next snippet choice'     })
end)

vim.keymap.set('s', '<Tab>',   function() ls.jump(1) end,  { desc = 'Jump to next place in snippet' })
vim.keymap.set('s', '<S-Tab>', function() ls.jump(-1) end, { desc = 'Jump to previous place in snippet' })

-- `<Tab>`/`<S-Tab>` in insert mode can conflict with snippet-expansion
-- keymaps, use these keymaps to to explicitly jump without expanding
-- snippets
vim.keymap.set({ 'i', 's' }, '<M-l>',     function() ls.jump(1) end,  { desc = 'Jump to next place in snippet' })
vim.keymap.set({ 'i', 's' }, '<M-h>',     function() ls.jump(-1) end, { desc = 'Jump to previous place in snippet' })
vim.keymap.set({ 'i', 's' }, '<M-Right>', function() ls.jump(1) end,  { desc = 'Jump to next place in snippet' })
vim.keymap.set({ 'i', 's' }, '<M-Left>',  function() ls.jump(-1) end, { desc = 'Jump to previous place in snippet' })

vim.keymap.set('s', '<C-n>',  function() return ls.choice_active() and '<Plug>luasnip-next-choice' or '<C-n>' end,  { expr = true, desc = 'Select next choice node in snippet' })
vim.keymap.set('s', '<C-p>',  function() return ls.choice_active() and '<Plug>luasnip-prev-choice' or '<C-p>' end,  { expr = true, desc = 'Select next choice node in snippet' })
vim.keymap.set('s', '<Down>', function() return ls.choice_active() and '<Plug>luasnip-next-choice' or '<Down>' end, { expr = true, desc = 'Select next choice node in snippet' })
vim.keymap.set('s', '<Up>',   function() return ls.choice_active() and '<Plug>luasnip-prev-choice' or '<Up>' end,   { expr = true, desc = 'Select next choice node in snippet' })
-- stylua: ignore end
