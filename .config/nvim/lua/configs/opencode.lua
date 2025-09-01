-- Default configuration with all available options
require('opencode').setup({
  default_global_keymaps = false,
  ui = {
    icons = { preset = vim.g.has_nf and 'emoji' or 'text' },
    input = { text = { wrap = true } },
  },
  context = {
    cursor_data = true,
  },
  keymap = {
    window = {
      toggle_pane = false, -- default overrides `<Tab>` in insert mode
      submit_insert = '<M-CR>',
      close = '<C-c>',
    },
  },
})

local opencode_api = require('opencode.api')

-- stylua: ignore start
vim.keymap.set('n', '<Leader>@', opencode_api.toggle_focus, { desc = 'Toggle focus between opencode and last window' })
vim.keymap.set('n', ']@', opencode_api.diff_next, { desc = 'Navigate to opencode next file diff' })
vim.keymap.set('n', '[@', opencode_api.diff_prev, { desc = 'Navigate to opencode previous file diff' })
-- stylua: ignore end

vim.api.nvim_create_autocmd('FileType', {
  desc = 'Filetype settings for opencode buffers.',
  pattern = {
    'opencode_input',
    'opencode_output',
  },
  group = vim.api.nvim_create_augroup('my.opencode.ft', {}),
  callback = function(args)
    vim.bo[args.buf].textwidth = 0
    vim.bo[args.buf].filetype = 'markdown'
    vim.b[args.buf].winbar_no_attach = true
  end,
})

local function set_default_hlgroups()
  local hl = require('utils.hl')

  -- See `lua/core/autocmds.lua` for `hl-NormalSpecial` definition
  hl.set_default(
    0,
    'OpenCodeNormal',
    { link = 'NormalSpecial', default = true }
  )
  hl.set_default(
    0,
    'OpenCodeBackground',
    { link = 'NormalSpecial', default = true }
  )
  hl.set_default(0, 'OpenCodeDiffAdd', { link = 'DiffAdd', default = true })
  hl.set_default(
    0,
    'OpencodeDiffDelete',
    { link = 'DiffDelete', default = true }
  )
  hl.set_default(0, 'OpencodeAgentBuild', { link = 'Todo', default = true })
  hl.set_default(
    0,
    'OpencodeInputLegend',
    { link = 'SpecialKey', default = true }
  )
  hl.set_default(0, 'OpenCodeSessionDescription', {
    bg = 'OpenCodeNormal',
    fg = 'Comment',
    default = true,
  })
  hl.set_default(0, 'OpenCodeHint', {
    bg = 'OpenCodeNormal',
    fg = 'Comment',
    default = true,
  })
end

set_default_hlgroups()

vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('my.opencode.hl', {}),
  desc = 'Set default highlight groups for opencode.nvim.',
  callback = set_default_hlgroups,
})
