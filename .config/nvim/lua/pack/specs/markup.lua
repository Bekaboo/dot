return {
  {
    src = 'https://github.com/lervag/vimtex',
    data = {
      cmds = 'VimtexInverseSearch',
      events = {
        event = 'Filetype',
        pattern = 'tex',
      },
    },
  },

  {
    src = 'https://github.com/iamcco/markdown-preview.nvim',
    data = {
      build = 'cd app && npm install && cd - && git restore .',
      events = {
        event = 'Filetype',
        pattern = 'markdown',
      },
    },
  },

  {
    src = 'https://github.com/dhruvasagar/vim-table-mode',
    data = {
      events = {
        event = 'Filetype',
        pattern = 'markdown',
      },
    },
  },

  {
    src = 'https://github.com/jmbuhr/otter.nvim',
    data = {
      events = {
        event = 'Filetype',
        pattern = 'markdown',
      },
    },
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
    src = 'https://github.com/benlubas/molten-nvim',
    data = {
      build = ':UpdateRemotePlugins',
      -- No need to lazy load on molten's builtin commands (e.g. `:MoltenInit`)
      -- since they are already registered in rplugin manifest,
      -- see `:h $NVIM_RPLUGIN_MANIFEST`
      -- Below are extra commands defined in `lua/configs/molten.lua`
      cmds = {
        'MoltenNotebookRunLine',
        'MoltenNotebookRunCellAbove',
        'MoltenNotebookRunCellBelow',
        'MoltenNotebookRunCellCurrent',
        'MoltenNotebookRunVisual',
        'MoltenNotebookRunOperator',
      },
      load = function()
        local loaded = false

        ---Lazy-load molten plugin on keys
        ---@param mode string in which mode to set the triggering keymap
        ---@param key string the key to trigger molten plugin
        ---@param opts vim.keymap.set.Opts? the keymap options
        local function load_on_key(mode, key, opts)
          if loaded then
            return
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
          load_on_key('x', '<CR>', { buffer = buf, desc = 'Run current cell' })

          -- Jupyter notebook only keymaps
          if vim.bo[buf].ft == 'markdown' then
            -- stylua: ignore start
            load_on_key('n', '<CR>', { buffer = buf, desc = 'Run current cell' })
            load_on_key('n', '<LocalLeader>k', { buffer = buf, desc = 'Run current cell and all above' })
            load_on_key('n', '<LocalLeader>j', { buffer = buf, desc = 'Run current cell and all below' })
            load_on_key('n', '<LocalLeader><CR>', { buffer = buf, desc = 'Run code selected by operator' })
            -- stylua: ignore end
          end
        end

        require('utils.load').on_events(
          { event = 'FileType', pattern = { 'python', 'markdown' } },
          'molten',
          function(args)
            if loaded then
              return
            end
            set_triggers(args.buf)
          end
        )
      end,
    },
  },

  {
    src = 'https://github.com/HakonHarnes/img-clip.nvim',
    data = {
      load = function()
        local load = require('utils.load')

        load.on_events(
          'UIEnter',
          'img-clip',
          vim.schedule_wrap(function()
            load.load('img-clip')
          end)
        )
      end,
    },
  },
}
