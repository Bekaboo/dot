return {
  src = 'https://github.com/sudo-tee/opencode.nvim',
  data = {
    deps = 'https://github.com/nvim-lua/plenary.nvim',
    cmds = {
      'OpencodeSwapPosition',
      'Opencode',
      'OpencodeToggleFocus',
      'OpencodeOpenInput',
      'OpencodeOpenInputNewSession',
      'OpencodeOpenOutput',
      'OpencodeClose',
      'OpencodeStop',
      'OpencodeSelectSession',
      'OpencodeTogglePane',
      'OpencodeConfigureProvider',
      'OpencodeRun',
      'OpencodeRunNewSession',
      'OpencodeDiff',
      'OpencodeDiffNext',
      'OpencodeDiffPrev',
      'OpencodeDiffClose',
      'OpencodeRevertAllLastPrompt',
      'OpencodeRevertThisLastPrompt',
      'OpencodeRevertAllSession',
      'OpencodeRevertThisSession',
      'OpencodeRevertAllToSnapshot',
      'OpencodeRevertThisToSnapshot',
      'OpencodeRestoreSnapshotFile',
      'OpencodeRestoreSnapshotAll',
      'OpencodeSetReviewBreakpoint',
      'OpencodeInit',
      'OpencodeHelp',
      'OpencodeMCP',
      'OpencodeConfigFile',
      'OpencodeAgentPlan',
      'OpencodeAgentBuild',
      'OpencodeAgentSelect',
    },
    keys = {
      lhs = '<Leader>@',
      opts = { desc = 'Toggle focus between opencode and last window' },
    },
    postload = function()
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
      vim.keymap.set('n', '[@', opencode_api.diff_prev, { desc = 'Navigate to opencode previous file diff' })
      vim.keymap.set('n', ']@', opencode_api.diff_next, { desc = 'Navigate to opencode next file diff' })
      -- stylua: ignore end

      local ft_group = vim.api.nvim_create_augroup('my.opencode.ft', {})

      vim.api.nvim_create_autocmd('FileType', {
        desc = 'Filetype settings for opencode buffers.',
        pattern = 'opencode*',
        group = ft_group,
        callback = function(args)
          vim.api.nvim_buf_call(args.buf, function()
            vim.opt_local.colorcolumn = ''
            vim.b.winbar_no_attach = true
          end)
        end,
      })

      vim.api.nvim_create_autocmd('FileType', {
        desc = 'Filetype settings for opencode buffers.',
        pattern = 'opencode_output',
        group = ft_group,
        callback = function(args)
          vim.bo[args.buf].filetype = 'markdown'
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
    end,
  },
}
