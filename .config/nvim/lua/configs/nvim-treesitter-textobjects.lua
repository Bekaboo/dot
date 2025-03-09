---@diagnostic disable-next-line: missing-fields
require('nvim-treesitter.configs').setup({
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
