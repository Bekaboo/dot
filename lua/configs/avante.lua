local avante = require('avante')
local avante_api = require('avante.api')

avante.setup({
  behaviour = {
    auto_set_keymaps = false,
  },
  mappings = {
    ask = '<Leader>@',
    edit = '<Leader>.',
    refresh = '<C-l>',
    focus = '<Leader>@',
    diff = {
      ours = 'c<',
      theirs = 'c>',
      all_theirs = 'c+',
      both = 'c=',
      cursor = 'c.',
      next = ']x',
      prev = '[x',
    },
    suggestion = {
      accept = '<M-l>',
      next = '<M-]>',
      prev = '<M-[>',
      dismiss = '<C-]>',
    },
    jump = {
      next = ']]',
      prev = '[[',
    },
    submit = {
      normal = '<CR>',
      insert = '<CR>',
    },
    sidebar = {
      switch_windows = '<M-C-]>',
      reverse_switch_windows = '<M-Esc>',
    },
  },
  windows = {
    width = 32,
    sidebar_header = {
      align = 'center',
      rounded = false,
    },
    edit = {
      border = 'solid',
      start_inset = true,
    },
    ask = {
      border = 'solid',
      start_inset = true,
    },
  },
  hints = {
    enabled = false,
  },
  highlights = {
    diff = {
      current = 'DiffDeleted',
      incoming = 'DiffAdd',
    },
  },
  diff = {
    autojump = true,
    list_opener = 'copen',
  },
})

vim.keymap.set('n', '<Leader>@', avante_api.ask)
vim.keymap.set('x', '<Leader>@', avante_api.ask)
vim.keymap.set('x', '<Leader>.', avante_api.edit)

vim.api.nvim_create_autocmd('FileType', {
  desc = 'Buffer-local settings for avante buffers.',
  group = vim.api.nvim_create_augroup('AvanteSetup', {}),
  pattern = 'Avante*',
  callback = function(info)
    local buf = info.buf
    -- Disable/set some buf-local keymaps in avante buffers
    if info.match == 'Avante' then
      vim.keymap.set('n', 'q', 'q', { buffer = buf })
      vim.keymap.set('n', '<Esc>', '<Esc>', { buffer = buf })
      vim.keymap.set({ 'n', 'v' }, '<C-l>', function()
        if vim.v.hlsearch == 1 then
          vim.cmd.nohl()
          return
        end
        avante_api.refresh()
      end, { buffer = buf })
    end

    -- Load markdown settings, syntax highlights, etc. for avante and avante
    -- input buffers
    vim.bo[buf].ft = 'markdown'

    -- Never show other buffers in avante windows
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      vim.wo[win].winfixbuf = true
    end
  end,
})
