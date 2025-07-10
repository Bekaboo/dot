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

-- Unlink current snippet on leaving insert/selection mode
-- https://github.com/L3MON4D3/LuaSnip/issues/258#issuecomment-1011938524
vim.api.nvim_create_autocmd('ModeChanged', {
  desc = 'Unlink current snippet on leaving insert/selection mode.',
  group = vim.api.nvim_create_augroup('LuaSnipModeChanged', {}),
  callback = function(args)
    local mode = vim.v.event.new_mode ---@diagnostic disable-line: undefined-field
    local omode = vim.v.event.old_mode ---@diagnostic disable-line: undefined-field
    if
      (omode == 's' and mode == 'n' or omode == 'i')
      and ls.session.current_nodes[args.buf]
      and not ls.session.jump_active
    then
      ls.unlink_current()
    end
  end,
})

-- stylua: ignore start
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
