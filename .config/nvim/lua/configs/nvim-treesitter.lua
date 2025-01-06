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
  },
  auto_install = false,
  sync_install = false,
  ignore_install = {},
  highlight = {
    enable = not vim.g.vscode,
    disable = function(lang, buf)
      return lang == 'latex'
        or lang == 'tmux'
        or vim.b[buf].bigfile
        or vim.fn.win_gettype() == 'command'
    end,
    -- Enable additional vim regex highlighting
    -- in markdown files to get vimtex math conceal
    additional_vim_regex_highlighting = { 'markdown' },
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
