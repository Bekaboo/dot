local ts_configs = require('nvim-treesitter.configs')
local ts_parsers = require('nvim-treesitter.parsers')

-- HACK: improve file reading speed: first read the file then load modules
ts_configs.reattach_module = vim.schedule_wrap(ts_configs.reattach_module)
ts_configs.setup = vim.schedule_wrap(ts_configs.setup)

-- Fix: invalid buffer id cause by hack above
ts_parsers.get_buf_lang = (function(cb)
  ---@param buf number? or current buffer
  ---@return string
  return function(buf, ...)
    if buf and not vim.api.nvim_buf_is_valid(buf) then
      return ''
    end
    return cb(buf, ...)
  end
end)(ts_parsers.get_buf_lang)

---@diagnostic disable-next-line: missing-fields
ts_configs.setup({
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
  },
  auto_install = true,
  sync_install = false,
  ignore_install = {},
  highlight = {
    enable = not vim.g.vscode,
    disable = function(lang, buf)
      return vim.b[buf].bigfile
        or vim.fn.win_gettype() == 'command'
        or vim.b[buf].vimtex_id and lang == 'latex'
        -- Tmux ts is buggy, comments highlighted as code, see:
        -- - https://github.com/Freed-Wu/tree-sitter-tmux/issues/26
        -- - https://github.com/Freed-Wu/tree-sitter-tmux/issues/25
        or lang == 'tmux'
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

-- Text object for treesitter nodes
vim.keymap.set('o', 'in', '<Cmd>silent! normal van<CR>', {
  noremap = false,
  desc = 'Inside named node',
})
vim.keymap.set('o', 'an', '<Cmd>silent! normal van<CR>', {
  noremap = false,
  desc = 'Around named node',
})
