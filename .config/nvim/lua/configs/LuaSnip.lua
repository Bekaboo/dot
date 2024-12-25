local ls = require('luasnip')
local ls_types = require('luasnip.util.types')
local ls_ft = require('luasnip.extras.filetype_functions')
local static = require('utils.static')

---Filetypes for which snippets have been loaded
---@type table<string, boolean>
local loaded_fts = {}

---Load snippets for a given filetype
---@param ft string
---@return nil
local function load_snippets(ft)
  if loaded_fts[ft] then
    return
  end
  loaded_fts[ft] = true

  local ok, snip_groups = pcall(require, 'snippets.' .. ft)
  if ok then
    for _, snip_group in pairs(snip_groups) do
      ls.add_snippets(ft, snip_group.snip or snip_group, snip_group.opts or {})
    end
  end
end

-- Trigger markdown snippets when filetype is 'markdown_inline' or 'html' or
-- 'html_inline' (lang returned from treesitter when using
-- `from_pos_or_filetype()` as the filetype function)
local lang_ft_map = {
  markdown_inline = { 'markdown' },
  html_inline = { 'html' },
  html = { 'markdown' },
}

for lang, fts in pairs(lang_ft_map) do
  ls.filetype_extend(lang, fts)
end

ls.setup({
  ft_func = function()
    local langs = ls_ft.from_pos_or_filetype()
    for _, lang in ipairs(langs) do
      load_snippets(lang)
      for _, ft in ipairs(lang_ft_map[lang] or {}) do
        load_snippets(ft)
      end
    end
    return langs
  end,
  keep_roots = true,
  link_roots = true,
  exit_roots = false,
  link_children = true,
  enable_autosnippets = true,
  store_selection_keys = '<Tab>',
  ext_opts = {
    [ls_types.choiceNode] = {
      active = {
        virt_text = { { static.icons.ArrowLeftRight, 'Number' } },
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

-- stylua: ignore start
vim.keymap.set('s', '<Tab>',   function() ls.jump(1) end, { desc = 'Jump to previous place in snippet' })
vim.keymap.set('s', '<S-Tab>', function() ls.jump(-1) end, { desc = 'Jump to next place in snippet' })
vim.keymap.set('s', '<C-n>',   function() return ls.choice_active() and '<Plug>luasnip-next-choice' or '<C-n>' end, { expr = true, desc = 'Select next choice node in snippet' })
vim.keymap.set('s', '<C-p>',   function() return ls.choice_active() and '<Plug>luasnip-prev-choice' or '<C-p>' end, { expr = true, desc = 'Select next choice node in snippet' })
-- stylua: ignore end
