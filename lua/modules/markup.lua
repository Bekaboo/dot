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
    enabled = not vim.g.no_nf,
    ft = 'markdown',
    build = 'cd app && npm install && cd - && git restore .',
    config = function()
      require('configs.markdown-preview')
    end,
  },

  {
    'dhruvasagar/vim-table-mode',
    cmd = 'TableModToggle',
    ft = 'markdown',
    config = function()
      require('configs.vim-table-mode')
    end,
  },

  {
    'jmbuhr/otter.nvim',
    ft = { 'markdown' },
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
      local function load(mode, key, buf)
        vim.keymap.set(mode, key, function()
          require('molten.status')
          vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes(key, true, true, true),
            'im',
            false
          )
        end, { buffer = buf })
      end

      vim.api.nvim_create_autocmd('FileType', {
        desc = 'Lazy-load molten on keys in python or markdown files.',
        group = vim.api.nvim_create_augroup('MoltenLazyLoadKeys', {}),
        pattern = { 'python', 'markdown' },
        callback = function(info)
          -- Markdown buffers that is not a Jupyter Notebook -- not something
          -- that we want to load molten on
          if
            info.match == 'markdown'
            and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(info.buf), ':e')
              ~= 'ipynb'
          then
            return
          end

          load('x', '<CR>', info.buf) -- for both python and notebook buffers
          if info.match == 'markdown' then
            load('x', '<CR>', info.buf)
            load('n', '<CR>', info.buf)
            load('n', '<LocalLeader>k', info.buf)
            load('n', '<LocalLeader>j', info.buf)
            load('n', '<LocalLeader><CR>', info.buf)
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
    'lukas-reineke/headlines.nvim',
    ft = { 'markdown', 'norg', 'org', 'qml' },
    dependencies = 'nvim-treesitter/nvim-treesitter',
    config = function()
      require('configs.headlines')
    end,
  },
}
