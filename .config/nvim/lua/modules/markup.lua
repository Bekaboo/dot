return {
  {
    'lervag/vimtex',
    ft = { 'tex', 'markdown' },
    config = function()
      require('configs.vimtex')
    end,
  },

  {
    'iamcco/markdown-preview.nvim',
    ft = 'markdown',
    build = 'cd app && npm install && cd - && git restore .',
    config = function()
      require('configs.markdown-preview')
    end,
  },

  {
    'dhruvasagar/vim-table-mode',
    cmd = { 'TableModeToggle', 'TableModeEnable', 'TableModeRealign' },
    event = 'BufWritePre',
    init = function()
      vim.g.table_mode_syntax = 0
      vim.g.table_mode_disable_mappings = 1
      vim.g.table_mode_disable_tableize_mappings = 1
    end,
    config = function()
      require('configs.vim-table-mode')
    end,
  },

  {
    'jmbuhr/otter.nvim',
    ft = 'markdown',
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
    },
    config = function()
      require('configs.otter')
    end,
  },

  {
    'benlubas/molten-nvim',
    init = function()
      ---Lazy-load molten plugin on keys
      ---@param mode string in which mode to set the triggering keymap
      ---@param key string the key to trigger molten plugin
      ---@param buf number the buffer to set the keymap
      ---@param opts vim.keymap.set.Opts? the keymap options
      local function load(mode, key, buf, opts)
        vim.keymap.set(mode, key, function()
          require('molten.status')
          vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes(key, true, true, true),
            'im',
            false
          )
        end, vim.tbl_deep_extend('force', { buffer = buf }, opts or {}))
      end

      vim.api.nvim_create_autocmd('FileType', {
        desc = 'Lazy-load molten on keys in python or markdown files.',
        group = vim.api.nvim_create_augroup('MoltenLazyLoadKeys', {}),
        pattern = { 'python', 'markdown' },
        callback = function(info)
          -- Skip for non-notebook markdown files
          if
            info.match == 'markdown'
            and vim.fn.fnamemodify(info.file, ':e') ~= 'ipynb'
          then
            return
          end

          load('x', '<CR>', info.buf, { desc = 'Run current cell' }) -- for both python and notebook buffers
          if info.match == 'markdown' then
            -- stylua: ignore start
            load('n', '<CR>', info.buf, { desc = 'Run current cell' })
            load('n', '<LocalLeader>k', info.buf, { desc = 'Run current cell and all above' })
            load('n', '<LocalLeader>j', info.buf, { desc = 'Run current cell and all below' })
            load('n', '<LocalLeader><CR>', info.buf, { desc = 'Run code selected by operator' })
            -- stylua: ignore end
          end
          return true
        end,
      })
    end,
    -- No need to lazy load on molten's builtin commands (e.g. `:MoltenInit`)
    -- since they are already registered in rplugin manifest,
    -- see `:h $NVIM_RPLUGIN_MANIFEST`
    -- Below are extra commands defined in `lua/configs/molten.lua`
    cmd = {
      'MoltenNotebookRunLine',
      'MoltenNotebookRunCellAbove',
      'MoltenNotebookRunCellBelow',
      'MoltenNotebookRunCellCurrent',
      'MoltenNotebookRunVisual',
      'MoltenNotebookRunOperator',
    },
    build = ':UpdateRemotePlugins',
    config = function()
      require('configs.molten')
    end,
  },

  {
    'HakonHarnes/img-clip.nvim',
    ft = {
      'markdown',
      'vimwiki',
      'html',
      'org',
      'rst',
      'tex',
      'typst',
      'asciidoc',
    },
    config = function()
      require('configs.img-clip')
    end,
  },
}
