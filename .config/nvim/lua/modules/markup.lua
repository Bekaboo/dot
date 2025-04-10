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
    build = 'cd app && npm install && cd - && git restore .',
    lazy = true,
    init = function()
      vim.api.nvim_create_autocmd('FileType', {
        desc = 'Defer loading markdown-preview in markdown files.',
        group = vim.api.nvim_create_augroup('MarkdownPreviewDeferLoading', {}),
        pattern = 'markdown',
        once = true,
        callback = vim.schedule_wrap(function()
          require('lazy.core.loader').load(
            'markdown-preview.nvim',
            { ft = 'markdown' }
          )
          vim.api.nvim_exec_autocmds('FileType', { pattern = 'markdown' })
        end),
      })
    end,
    config = function()
      require('configs.markdown-preview')
    end,
  },

  {
    'dhruvasagar/vim-table-mode',
    lazy = true,
    init = function()
      vim.api.nvim_create_autocmd('FileType', {
        desc = 'Defer loading vim-table-mode in markdown files.',
        group = vim.api.nvim_create_augroup('VimTableModeDeferLoading', {}),
        pattern = 'markdown',
        once = true,
        callback = vim.schedule_wrap(function()
          require('lazy.core.loader').load(
            'vim-table-mode',
            { ft = 'markdown' }
          )
        end),
      })
    end,
    config = function()
      require('configs.vim-table-mode')
    end,
  },

  {
    'jmbuhr/otter.nvim',
    lazy = true,
    init = function()
      vim.api.nvim_create_autocmd('FileType', {
        desc = 'Defer loading otter.nvim in markdown files.',
        group = vim.api.nvim_create_augroup('OtterDeferLoading', {}),
        pattern = 'markdown',
        once = true,
        callback = vim.schedule_wrap(function()
          require('otter')
        end),
      })
    end,
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

        if
          vim.bo[buf].ft ~= 'python'
          and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':e')
            ~= 'ipynb'
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
    lazy = true,
    init = function()
      -- Load img-clip when `vim.paste` is invoked
      vim.paste = (function(cb)
        return function(...)
          vim.paste = cb
          pcall(require, 'img-clip')
          vim.paste(...)
        end
      end)(vim.paste)

      -- Setup keymaps in some file types
      vim.api.nvim_create_autocmd('FileType', {
        desc = 'Lazy-load img-clip on keys.',
        group = vim.api.nvim_create_augroup('ImgClipLazyLoadKeys', {}),
        once = true,
        pattern = {
          'markdown',
          'vimwiki',
          'html',
          'org',
          'rst',
          'tex',
          'typst',
          'asciidoc',
        },
        callback = function(info)
          vim.keymap.set('n', '<Leader>p', function()
            require('img-clip').paste_image()
          end, { buffer = info.buf, desc = 'Paste image' })
        end,
      })
    end,
    config = function()
      require('configs.img-clip')
    end,
  },
}
