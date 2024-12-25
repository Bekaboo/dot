local ts_configs = require('nvim-treesitter.configs')

---@diagnostic disable-next-line: missing-fields
ts_configs.setup({
  -- Make sure that we install all parsers shipped with neovim so that we don't
  -- end with using nvim-treesitter's queries and neovim's shipped parsers, which
  -- are incompatible with each other,
  -- see https://github.com/nvim-treesitter/nvim-treesitter/issues/3092
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
  endwise = {
    enable = true,
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
  textobjects = {
    select = {
      enable = true,
      lookahead = true, -- Automatically jump forward to textobj
      keymaps = {
        -- You can use the capture groups defined in textobjects.scm
        ['am'] = '@function.outer',
        ['im'] = '@function.inner',
        ['ao'] = '@loop.outer',
        ['io'] = '@loop.inner',
        ['ak'] = '@class.outer',
        ['ik'] = '@class.inner',
        ['a,'] = '@parameter.outer',
        ['i,'] = '@parameter.inner',
        ['a/'] = '@comment.outer',
        ['a*'] = '@comment.outer',
        ['ag'] = '@block.outer',
        ['ig'] = '@block.inner',
        ['a?'] = '@conditional.outer',
        ['i?'] = '@conditional.inner',
        ['a='] = '@assignment.outer',
        ['i='] = '@assignment.inner',
        ['a#'] = '@header.outer',
        ['i#'] = '@header.inner',
        ['a3'] = '@header.outer',
        ['i3'] = '@header.inner',
      },
      selection_modes = {
        ['@block.outer'] = 'V',
        ['@block.inner'] = 'V',
        ['@header.outer'] = 'V',
        ['@header.inner'] = 'V',
      },
    },
    move = {
      enable = true,
      set_jumps = true, -- whether to set jumps in the jumplist
      goto_next_start = {
        [']m'] = '@function.outer',
        [']o'] = '@loop.outer',
        [']]'] = '@function.outer',
        [']k'] = '@class.outer',
        ['],'] = '@parameter.outer',
        [']g'] = '@block.outer',
        [']?'] = '@conditional.outer',
        [']='] = '@assignment.inner',
        [']#'] = '@header.outer',
        [']3'] = '@header.outer',
      },
      goto_next_end = {
        [']M'] = '@function.outer',
        [']O'] = '@loop.outer',
        [']['] = '@function.outer',
        [']K'] = '@class.outer',
        [']<'] = '@parameter.outer',
        [']/'] = '@comment.outer',
        [']*'] = '@comment.outer',
        [']G'] = '@block.outer',
      },
      goto_previous_start = {
        ['[m'] = '@function.outer',
        ['[o'] = '@loop.outer',
        ['[['] = '@function.outer',
        ['[k'] = '@class.outer',
        ['[,'] = '@parameter.outer',
        ['[/'] = '@comment.outer',
        ['[*'] = '@comment.outer',
        ['[g'] = '@block.outer',
        ['[?'] = '@conditional.outer',
        ['[='] = '@assignment.inner',
        ['[#'] = '@header.outer',
        ['[3'] = '@header.outer',
      },
      goto_previous_end = {
        ['[M'] = '@function.outer',
        ['[O'] = '@loop.outer',
        ['[]'] = '@function.outer',
        ['[K'] = '@class.outer',
        ['[<'] = '@parameter.outer',
        ['[G'] = '@block.outer',
      },
    },
    swap = {
      enable = true,
      swap_next = {
        ['<M-C-L>'] = '@parameter.inner',
        ['<M-C-Right>'] = '@parameter.inner',
      },
      swap_previous = {
        ['<M-C-H>'] = '@parameter.inner',
        ['<M-C-Left>'] = '@parameter.inner',
      },
    },
    lsp_interop = {
      enable = true,
      border = 'solid',
      peek_definition_code = {
        ['<C-k>'] = '@function.outer',
      },
    },
  },
})
