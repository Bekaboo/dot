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

local hl = require('utils.hl')

hl.persist(function()
  -- See `lua/core/autocmds.lua` for `hl-NormalSpecial` definition
  -- stylua: ignore start
  hl.set_default(0, 'OpenCodeNormal',      { link = 'NormalSpecial' })
  hl.set_default(0, 'OpenCodeBackground',  { link = 'NormalSpecial' })
  hl.set_default(0, 'OpenCodeDiffAdd',     { link = 'DiffAdd'       })
  hl.set_default(0, 'OpencodeDiffDelete',  { link = 'DiffDelete'    })
  hl.set_default(0, 'OpencodeAgentBuild',  { link = 'Todo'          })
  hl.set_default(0, 'OpencodeInputLegend', { link = 'SpecialKey'    })

  hl.set_default(0, 'OpenCodeSessionDescription', { bg = 'OpenCodeNormal', fg = 'Comment' })
  hl.set_default(0, 'OpenCodeHint',               { bg = 'OpenCodeNormal', fg = 'Comment' })
  -- stylua: ignore end
end)
