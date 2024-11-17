local ts_configs = require('nvim-treesitter.configs')

---@param buf integer
---@return nil
local function enable_ts_folding(buf)
  -- Treesitter folding is extremely slow in large files,
  -- making typing and undo lag as hell
  --
  -- Also disable ts folding in markdown files because it
  -- is so slooow compared to other filetypes
  if
    not vim.api.nvim_buf_is_valid(buf)
    or vim.bo[buf].ft == 'markdown'
    or vim.b[buf].bigfile
  then
    return
  end
  vim.api.nvim_buf_call(buf, function()
    local o = vim.opt_local
    local fdm = o.fdm:get() ---@diagnostic disable-line: undefined-field
    local fde = o.fde:get() ---@diagnostic disable-line: undefined-field
    o.fdm = fdm == 'manual' and 'expr' or fdm
    o.fde = fde == '0' and 'nvim_treesitter#foldexpr()' or fde
  end)
end

enable_ts_folding(0)

-- Set treesitter folds
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('TSFolds', {}),
  callback = function(info)
    enable_ts_folding(info.buf)
  end,
})

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
    'cuda',
    'rust',
    'fish',
    'make',
    'javascript',
    'typescript',
  },
  auto_install = false,
  sync_install = false,
  ignore_install = {},
  highlight = {
    enable = not vim.g.vscode,
    disable = function(ft, buf)
      return ft == 'latex'
        or ft == 'tmux'
        or vim.b[buf].bigfile == true
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
