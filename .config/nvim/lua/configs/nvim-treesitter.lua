---@diagnostic disable-next-line: missing-fields
require('nvim-treesitter.configs').setup({
  -- Make sure that we install all parsers shipped with neovim so that we don't
  -- end up with using nvim-treesitter's queries and neovim's shipped parsers,
  -- which are incompatible with nvim-treesitter's
  -- See https://github.com/nvim-treesitter/nvim-treesitter/issues/3092
  ensure_installed = {
    -- Parsers shipped with neovim
    'c',
    'lua',
    'vim',
    'bash',
    'query',
    'python',
    'vimdoc',
    'markdown',
    'markdown_inline',
    -- Additional parsers
    'go',
    'cpp',
    'rust',
    'fish',
    'make',
    'html', -- for markdown inline highlight
    'latex',
  },
  auto_install = false,
  sync_install = false,
  ignore_install = {},
  highlight = {
    enable = not vim.g.vscode,
    disable = function(lang, buf)
      return vim.b[buf].bigfile
        or vim.fn.win_gettype() == 'command'
        or vim.b[buf].vimtex_id and lang == 'latex'
    end,
  },
  incremental_selection = {
    enable = true,
    keymaps = {
      init_selection = false,
      node_incremental = 'an',
      scope_incremental = 'aN',
      node_decremental = 'in',
    },
  },
})

-- stylua: ignore start
-- Text object for treesitter nodes
vim.keymap.set('o', 'in', '<Cmd>silent! normal van<CR>', { noremap = false, desc = 'Inside named node' })
vim.keymap.set('o', 'an', '<Cmd>silent! normal van<CR>', { noremap = false, desc = 'Around named node' })
-- stylua: ignore off
