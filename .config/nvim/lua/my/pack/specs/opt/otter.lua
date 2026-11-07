---@type my.pack.spec
return {
  src = 'https://github.com/jmbuhr/otter.nvim',
  data = {
    events = {
      event = 'FileType',
      pattern = 'markdown',
    },
    postload = function()
      local ot = require('otter')
      local utils = require('my.utils')

      -- Wrap `ot.activate()` in `pcall()` to suppress error when opening git diff
      -- for markdown files: 'Vim(append):Error executing lua callback: Vim:E95:
      -- Buffer with this name already exists'
      local ot_activate = ot.activate

      ---@diagnostic disable-next-line: duplicate-set-field
      function ot.activate(...)
        pcall(ot_activate, ...)
      end

      ot.setup({
        verbose = { no_code_found = false },
        buffers = { set_filetype = true },
        lsp = {
          root_dir = function()
            return utils.fs.root() or vim.fn.getcwd(0)
          end,
        },
      })

      local ot_supported_fts = { 'markdown', 'norg', 'org' }

      ---Activate otter for supported buffers
      ---@param buf integer
      ---@return nil
      local function ot_activate_supports_buf(buf)
        if
          not vim.api.nvim_buf_is_valid(buf)
          or not vim.tbl_contains(ot_supported_fts, vim.bo[buf].ft)
          or not vim.bo[buf].ma
          or not utils.ts.is_active(buf)
        then
          return
        end
        ot.activate(nil, nil, false)
      end

      -- Cater for lazy-loading, activate otter for existing buffers
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        ot_activate_supports_buf(buf)
      end

      vim.api.nvim_create_autocmd('FileType', {
        desc = 'Activate otter for filetypes with injections.',
        group = vim.api.nvim_create_augroup('my.otter.activate', {}),
        pattern = ot_supported_fts,
        callback = function(args)
          ot_activate_supports_buf(args.buf)
        end,
      })
    end,
  },
}
