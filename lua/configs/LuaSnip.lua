local ls = require('luasnip')
local ls_types = require('luasnip.util.types')
local static = require('utils.static')

ls.setup({
  keep_roots = true,
  link_roots = false,
  exit_roots = false,
  link_children = true,
  region_check_events = 'CursorMoved,CursorMovedI',
  delete_check_events = 'TextChanged,TextChangedI',
  enable_autosnippets = true,
  store_selection_keys = '<Tab>',
  ext_opts = {
    [ls_types.choiceNode] = {
      active = {
        virt_text = { { static.icons.Enum, 'Number' } },
      },
    },
    [ls_types.insertNode] = {
      unvisited = {
        virt_text = { { static.boxes.single.vt, 'NonText' } },
        virt_text_pos = 'inline',
      },
    },
    [ls_types.exitNode] = {
      unvisited = {
        virt_text = { { static.boxes.single.vt, 'NonText' } },
        virt_text_pos = 'inline',
      },
    },
  },
})

-- Unlink current snippet on leaving insert/selection mode
-- https://github.com/L3MON4D3/LuaSnip/issues/258#issuecomment-1011938524
vim.api.nvim_create_autocmd('ModeChanged', {
  desc = 'Unlink current snippet on leaving insert/selection mode.',
  group = vim.api.nvim_create_augroup('LuaSnipModeChanged', {}),
  callback = function(info)
    local mode = vim.v.event.new_mode
    local omode = vim.v.event.old_mode
    if
      (omode == 's' and mode == 'n' or omode == 'i')
      and ls.session.current_nodes[info.buf]
      and not ls.session.jump_active
    then
      ls.unlink_current()
    end
  end,
})

---Load snippets for a given filetype
---@param ft string
---@return nil
local function load_snippets(ft)
  local ok, snip_groups = pcall(require, 'snippets.' .. ft)
  if ok and type(snip_groups) == 'table' then
    for _, snip_group in pairs(snip_groups) do
      ls.add_snippets(ft, snip_group.snip or snip_group, snip_group.opts or {})
    end
  end
end

-- Lazy-load snippets based on filetype
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  load_snippets(vim.bo[buf].ft)
end
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('LuaSnipLazyLoadSnippets', {}),
  desc = 'Lazy load snippets for different filetypes.',
  callback = function(info)
    load_snippets(vim.bo[info.buf].ft)
  end,
})

-- stylua: ignore start
vim.keymap.set('s', '<Tab>',   function() ls.jump(1) end)
vim.keymap.set('s', '<S-Tab>', function() ls.jump(-1) end)
vim.keymap.set('s', '<C-n>',   function() return ls.choice_active() and '<Plug>luasnip-next-choice' or '<C-n>' end, { expr = true })
vim.keymap.set('s', '<C-p>',   function() return ls.choice_active() and '<Plug>luasnip-prev-choice' or '<C-p>' end, { expr = true })
-- stylua: ignore end
