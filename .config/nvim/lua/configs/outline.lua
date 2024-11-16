local icons = require('utils.static.icons')

require('outline').setup({
  outline_items = {
    show_symbol_details = false,
  },
  outline_window = {
    position = 'left',
    winhl = 'Normal:NormalSpecial',
  },
  preview_window = {
    border = 'solid',
    winhl = 'NormalFloat:NormalFloat',
  },
  symbols = {
    icon_fetcher = function(kind)
      return vim.g.has_nf and vim.trim(icons.kinds[kind]) or ''
    end,
  },
  symbol_folding = {
    markers = {
      vim.trim(icons.ui.AngleRight),
      vim.trim(icons.ui.AngleDown),
    },
  },
  providers = {
    priority = { 'lsp', 'coc', 'markdown', 'norg', 'asciidoc' },
  },
  keymaps = {
    show_help = 'g?',
    close = { '<C-w>c', '<C-w>q' },
    goto_location = '<CR>',
    peek_location = 'o',
    goto_and_close = '<S-Cr>',
    restore_location = '<C-g>',
    hover_symbol = 'K',
    toggle_preview = 'p',
    rename_symbol = 'r',
    code_actions = 'a',
    fold = 'zc',
    fold_toggle = { 'za', '=' },
    fold_toggle_all = 'zA',
    unfold = 'zo',
    fold_all = 'zM',
    unfold_all = 'zR',
    fold_reset = 'zx',
    down_and_jump = '<C-j>',
    up_and_jump = '<C-k>',
  },
})

vim.keymap.set('n', 'gO', '<Cmd>Outline<CR>', { desc = 'Toggle outline' })

local groupid = vim.api.nvim_create_augroup('OutlineSetup', {})
vim.api.nvim_create_autocmd('FileType', {
  desc = 'Set winfixbuf for outline buffers.',
  pattern = 'Outline',
  group = groupid,
  callback = vim.schedule_wrap(function()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].ft == 'Outline' then
        vim.wo[win].winfixbuf = true
      end
    end
  end),
})

local function set_default_hlgroups()
  require('utils.hl').set(0, 'OutlineCurrent', {
    link = 'Visual',
    bold = true,
  })
end
set_default_hlgroups()

vim.api.nvim_create_autocmd('ColorScheme', {
  desc = 'Set default hlgroups for outline.nvim.',
  group = groupid,
  callback = set_default_hlgroups,
})

local ol_cfg = require('outline.config')

---Update outline window width
---@return nil
local function ol_update_width()
  ol_cfg.o.outline_window.width =
    math.min(48, math.max(vim.o.winwidth, math.ceil(vim.o.columns / 4)))
end
ol_update_width()

vim.api.nvim_create_autocmd('VimResized', {
  desc = 'Update outline window width.',
  group = groupid,
  callback = ol_update_width,
})
