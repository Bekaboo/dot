return {
  {
    'lervag/vimtex',
    ft = 'tex',
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
    ft = 'markdown',
    keys = {
      { '<Leader>tm', desc = 'Table mode toggle' },
      { '<Leader>tt', desc = 'Table mode tableize' },
    },
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

  -- Python dependencies:
  -- - pynvim
  -- - ipykernel
  -- - jupyter_client
  --
  -- Optional:
  -- - cairosvg
  -- - kaleido
  -- - nbformat
  -- - plotly
  -- - pnglatex
  -- - pyperclip
  -- - pyqt6
  {
    'benlubas/molten-nvim',
    init = function()
      local loaded = false

      ---Lazy-load molten plugin on keys
      ---@param mode string in which mode to set the triggering keymap
      ---@param key string the key to trigger molten plugin
      ---@param buf number the buffer to set the keymap
      ---@param opts vim.keymap.set.Opts? the keymap options
      local function load_on_key(mode, key, buf, opts)
        if loaded then
          return
        end

        if not opts then
          opts = { buffer = buf }
        else
          opts.buffer = buf
        end

        vim.keymap.set(mode, key, function()
          require('molten.status')
          loaded = true
          vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes(key, true, true, true),
            'im',
            false
          )
        end, opts)
      end

      ---@param buf integer
      local function set_triggers(buf)
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end

        local ft = vim.bo[buf].ft
        if
          ft ~= 'python' and ft ~= 'markdown'
          or ft == 'markdown' -- don't load in normal markdown files
            and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':e') ~= 'ipynb'
        then
          return
        end

        -- For both python and notebook buffers
        load_on_key('x', '<CR>', buf, { desc = 'Run current cell' })

        -- Jupyter notebook only keymaps
        if vim.bo[buf].ft == 'markdown' then
          -- stylua: ignore start
          load_on_key('n', '<CR>', buf, { desc = 'Run current cell' })
          load_on_key('n', '<LocalLeader>k', buf, { desc = 'Run current cell and all above' })
          load_on_key('n', '<LocalLeader>j', buf, { desc = 'Run current cell and all below' })
          load_on_key('n', '<LocalLeader><CR>', buf, { desc = 'Run code selected by operator' })
          -- stylua: ignore end
        end
      end

      vim.api.nvim_create_autocmd('FileType', {
        desc = 'Lazy-load molten on keys in python or markdown files.',
        group = vim.api.nvim_create_augroup('MoltenLazyLoadKeys', {}),
        pattern = { 'python', 'markdown' },
        callback = function(info)
          if loaded then
            return true
          end
          set_triggers(info.buf)
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
