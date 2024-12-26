local ot = require('otter')
local utils = require('utils')

-- Wrap `ot.activate()` in `pcall()` to suppress error when opening git diff
-- for markdown files: 'Vim(append):Error executing lua callback: Vim:E95:
-- Buffer with this name already exists'
local _ot_activate = ot.activate
function ot.activate(...)
  pcall(_ot_activate, ...)
end

ot.setup({
  verbose = { no_code_found = false },
  buffers = { set_filetype = true },
  lsp = {
    root_dir = function()
      return vim.fs.root(0, utils.fs.root_patterns) or vim.fn.getcwd(0)
    end,
  },
})

vim.api.nvim_create_autocmd('FileType', {
  desc = 'Activate otter for filetypes with injections.',
  group = vim.api.nvim_create_augroup('OtterActivate', {}),
  pattern = { 'markdown', 'norg', 'org' },
  callback = function(info)
    local buf = info.buf
    if vim.bo[buf].ma and utils.ts.active(buf) then
      -- Enable completion only, disable diagnostics
      ot.activate({ 'python', 'bash', 'lua' }, true, false)
    end
  end,
})
