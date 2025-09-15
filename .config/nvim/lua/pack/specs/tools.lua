return {
  {
    src = 'https://github.com/ibhagwan/fzf-lua',
    data = {
      build = 'fzf --version',
      cmds = 'FzfLua',
      events = 'LspAttach',
      keys = {
        {
          lhs = '<C-_>',
          desc = 'Fuzzy complete command/search history',
          mode = 'c',
        },
        {
          lhs = '<C-x><C-l>',
          desc = 'Fuzzy complete command/search history',
          mode = 'c',
        },
        { lhs = '<C-r>?', desc = 'Fuzzy complete from registers', mode = 'i' },
        {
          lhs = '<C-r><C-_>',
          desc = 'Fuzzy complete from registers',
          mode = 'i',
        },
        {
          lhs = '<C-r><C-r>',
          desc = 'Fuzzy complete from registers',
          mode = 'i',
        },
        { lhs = '<C-x><C-f>', desc = 'Fuzzy complete path', mode = 'i' },
        { lhs = '<Leader>.', desc = 'Find files' },
        { lhs = "<Leader>'", desc = 'Resume last picker' },
        { lhs = '<Leader>`', desc = 'Find marks' },
        { lhs = '<Leader>,', desc = 'Find buffers' },
        { lhs = '<Leader>%', desc = 'Find tabpages' },
        { lhs = '<Leader>/', desc = 'Grep' },
        { lhs = '<Leader>?', desc = 'Find help files' },
        {
          lhs = '<Leader>*',
          mode = { 'n', 'x' },
          desc = 'Grep word under cursor',
        },
        {
          lhs = '<Leader>#',
          mode = { 'n', 'x' },
          desc = 'Grep word under cursor',
        },
        { lhs = '<Leader>"', desc = 'Find registers' },
        { lhs = '<Leader>:', desc = 'Find commands' },
        { lhs = '<Leader>F', desc = 'Find all available pickers' },
        { lhs = '<Leader>o', desc = 'Find oldfiles' },
        { lhs = '<Leader>-', desc = 'Find lines in buffer' },
        { lhs = '<Leader>=', desc = 'Find lines across buffers' },
        { lhs = '<Leader>-', desc = 'Find lines in selection', mode = 'x' },
        { lhs = '<Leader>=', desc = 'Find lines in selection', mode = 'x' },
        { lhs = '<Leader>n', desc = 'Find treesitter nodes' },
        { lhs = '<Leader>R', desc = 'Find symbol locations' },
        { lhs = '<Leader>f"', desc = 'Find registers' },
        {
          lhs = '<Leader>f*',
          mode = { 'n', 'x' },
          desc = 'Grep word under cursor',
        },
        {
          lhs = '<Leader>f#',
          mode = { 'n', 'x' },
          desc = 'Grep word under cursor',
        },
        { lhs = '<Leader>f:', desc = 'Find commands' },
        { lhs = '<Leader>f/', desc = 'Grep' },
        { lhs = '<Leader>fH', desc = 'Find highlights' },
        { lhs = "<Leader>f'", desc = 'Resume last picker' },
        { lhs = '<Leader>fA', desc = 'Find autocmds' },
        { lhs = '<Leader>fb', desc = 'Find buffers' },
        { lhs = '<Leader>fp', desc = 'Find tabpages' },
        { lhs = '<Leader>ft', desc = 'Find tags' },
        { lhs = '<Leader>fc', desc = 'Find changes' },
        { lhs = '<Leader>fd', desc = 'Find document diagnostics' },
        { lhs = '<Leader>fD', desc = 'Find workspace diagnostics' },
        { lhs = '<Leader>ff', desc = 'Find files' },
        { lhs = '<Leader>fa', desc = 'Find args' },
        { lhs = '<Leader>fl', desc = 'Find location list' },
        { lhs = '<Leader>fq', desc = 'Find quickfix list' },
        { lhs = '<Leader>fL', desc = 'Find location list stack' },
        { lhs = '<Leader>fQ', desc = 'Find quickfix stack' },
        { lhs = '<Leader>fgt', desc = 'Find git tags' },
        { lhs = '<Leader>fgs', desc = 'Find git stash' },
        { lhs = '<Leader>fgg', desc = 'Find git status' },
        { lhs = '<Leader>fgL', desc = 'Find git logs' },
        { lhs = '<Leader>fgl', desc = 'Find git buffer logs' },
        { lhs = '<Leader>fgb', desc = 'Find git branches' },
        { lhs = '<Leader>fgB', desc = 'Find git blame' },
        { lhs = '<Leader>gft', desc = 'Find git tags' },
        { lhs = '<Leader>gfs', desc = 'Find git stash' },
        { lhs = '<Leader>gfg', desc = 'Find git status' },
        { lhs = '<Leader>gfL', desc = 'Find git logs' },
        { lhs = '<Leader>gfl', desc = 'Find git buffer logs' },
        { lhs = '<Leader>gfb', desc = 'Find git branches' },
        { lhs = '<Leader>gfB', desc = 'Find git blame' },
        { lhs = '<Leader>fh', desc = 'Find help files' },
        { lhs = '<Leader>fk', desc = 'Find keymaps' },
        { lhs = '<Leader>f-', desc = 'Find lines in buffer' },
        { lhs = '<Leader>f-', desc = 'Find lines in selection', mode = 'x' },
        { lhs = '<Leader>f=', desc = 'Find lines across buffers' },
        { lhs = '<Leader>fm', desc = 'Find marks' },
        { lhs = '<Leader>fo', desc = 'Find oldfiles' },
        { lhs = '<Leader>fz', desc = 'Find directories from z' },
        { lhs = '<Leader>fw', desc = 'Find sessions (workspaces)' },
        { lhs = '<Leader>fn', desc = 'Find treesitter nodes' },
        { lhs = '<Leader>fs', desc = 'Find lsp symbols or treesitter nodes' },
        { lhs = '<Leader>fSa', desc = 'Find code actions' },
        { lhs = '<Leader>fSd', desc = 'Find symbol definitions' },
        { lhs = '<Leader>fSD', desc = 'Find symbol declarations' },
        { lhs = '<Leader>fS<C-d>', desc = 'Find symbol type definitions' },
        { lhs = '<Leader>fSs', desc = 'Find symbol in current document' },
        { lhs = '<Leader>fSS', desc = 'Find symbol in whole workspace' },
        { lhs = '<Leader>fSi', desc = 'Find symbol implementations' },
        { lhs = '<Leader>fS<', desc = 'Find symbol incoming calls' },
        { lhs = '<Leader>fS>', desc = 'Find symbol outgoing calls' },
        { lhs = '<Leader>fSr', desc = 'Find symbol references' },
        { lhs = '<Leader>fSR', desc = 'Find symbol locations' },
        { lhs = '<Leader>fF', desc = 'Find all available pickers' },
      },
      init = function()
        -- Disable fzf's default vim plugin
        vim.g.loaded_fzf = 1

        ---@diagnostic disable-next-line: duplicate-set-field
        vim.ui.select = function(...)
          local fzf_ui = require('fzf-lua.providers.ui_select')
          -- Register fzf as custom `vim.ui.select()` function if not yet
          -- registered
          if not fzf_ui.is_registered() then
            local ui_select = fzf_ui.ui_select

            ---Overriding fzf-lua's default `ui_select()` function to use a
            ---custom prompt
            ---@diagnostic disable-next-line: duplicate-set-field
            fzf_ui.ui_select = function(items, opts, on_choice)
              -- Hack: use nbsp after ':' here because currently fzf-lua does
              -- not allow custom prompt and force substitute pattern ':%s?$'
              -- in `opts.prompt` to '> ' as the fzf prompt. We WANT the column
              -- in the prompt, so use nbsp to avoid this substitution.
              -- Also, don't use `opts.prompt:gsub(':?%s*$', ':\xc2\xa0')` here
              -- because it does a non-greedy match and will not substitute
              -- ':' at the end of the prompt, e.g. if `opts.prompt` is
              -- 'foobar: ' then result will be 'foobar: : ', interestingly
              -- this behavior changes in Lua 5.4, where the match becomes
              -- greedy, i.e. given the same string and substitution above the
              -- result becomes 'foobar> ' as expected.
              opts.prompt = opts.prompt
                and vim.fn.substitute(
                  opts.prompt,
                  ':\\?\\s*$',
                  ':\xc2\xa0',
                  ''
                )
              ui_select(items, opts, on_choice)
            end

            -- Use the register function provided by fzf-lua. We are using this
            -- wrapper instead of directly replacing `vim.ui.selct()` with fzf
            -- select function because in this way we can pass a callback to this
            -- `register()` function to generate fzf opts in different contexts,
            -- see https://github.com/ibhagwan/fzf-lua/issues/755
            -- Here we use the callback to achieve adaptive height depending on
            -- the number of items, with a max height of 10, the `split` option
            -- is basically the same as that used in fzf config file:
            -- lua/configs/fzf-lua.lua
            fzf_ui.register(function(_, items)
              local height = #items + 1
              return {
                winopts = {
                  split = string.format(
                    -- Don't shrink size if a quickfix list is closed for fzf
                    -- window to avoid window resizing and content shifting
                    '%s | if get(g:, "_fzf_qfclosed", "") == "" && %d < winheight(0) | resize %d | let g:_fzf_height = %d | endif',
                    vim.trim(
                      require('fzf-lua.config').setup_opts.winopts.split
                    ),
                    height,
                    height,
                    height
                  ),
                },
              }
            end)
          end
          vim.ui.select(...)
        end
      end,
    },
  },

  {
    src = 'https://github.com/lewis6991/gitsigns.nvim',
    data = {
      events = { 'BufReadPre', 'SessionLoadPost' },
      cmds = 'Gitsigns',
      keys = { lhs = '<Leader>gG', desc = 'Git list repo hunks' },
    },
  },

  {
    src = 'https://github.com/akinsho/git-conflict.nvim',
    data = {
      events = 'BufReadPre',
    },
  },

  {
    src = 'https://github.com/tpope/vim-fugitive',
    data = {
      cmds = {
        'G',
        'GBrowse',
        'Gcd',
        'Gclog',
        'Gdiffsplit',
        'Gdrop',
        'Gedit',
        'Ggrep',
        'Git',
        'Glcd',
        'Glgrep',
        'Gllog',
        'Gpedit',
        'Gread',
        'Gsplit',
        'Gtabedit',
        'Gvdiffsplit',
        'Gvsplit',
        'Gwq',
        'Gwrite',
      },
      keys = {
        { lhs = '<Leader>gL', desc = 'Git log entire repo' },
        { lhs = '<Leader>g<Space>', desc = 'Populate cmdline with ":Git"' },
      },
      events = { 'BufNew', 'BufWritePost', 'BufReadPre' },
      deps = {
        -- Enable :GBrowse command in GitHub/Gitlab repos
        'https://github.com/tpope/vim-rhubarb',
        'https://github.com/shumphrey/fugitive-gitlab.vim',
      },
    },
  },

  {
    src = 'https://github.com/NvChad/nvim-colorizer.lua',
    data = {
      events = {
        'BufNew',
        'BufRead',
        'BufWritePost',
        'TextChanged',
        'TextChangedI',
        'StdinReadPre',
      },
    },
  },

  {
    src = 'https://github.com/stevearc/oil.nvim',
    data = {
      cmds = 'Oil',
      load = function() -- Load oil on startup only when editing a directory
        vim.g.loaded_fzf_file_explorer = 0
        vim.g.loaded_netrw = 0
        vim.g.loaded_netrwPlugin = 0
        vim.api.nvim_create_autocmd('BufEnter', {
          nested = true,
          -- Use `vim.schedule()` here to wait session to be loaded and
          -- buffer attributes, e.g. buffer name, to be updated before
          -- checking if the buffer is a directory buffer
          callback = vim.schedule_wrap(function(args)
            local buf = args.buf
            local id = args.id

            if
              not vim.api.nvim_buf_is_valid(buf)
              or vim.fn.bufwinid(buf) == -1
              or vim.bo[buf].bt ~= ''
            then
              return
            end

            local bufname = vim.api.nvim_buf_get_name(buf)
            if bufname == '' then
              return
            end

            -- Only load oil.nvim if the buffer is a non-existing file
            -- (e.g. scp:// or oil:// paths) or is an existing directory
            local stat = vim.uv.fs_stat(bufname)
            if stat and stat.type ~= 'directory' then
              return
            end

            pcall(require, 'oil')
            pcall(vim.api.nvim_del_autocmd, id)
          end),
        })
      end,
    },
  },

  {
    src = 'https://github.com/stevearc/quicker.nvim',
    data = {
      load = function()
        local load = require('utils.load')

        load.on_events(
          'UIEnter',
          'quicker',
          vim.schedule_wrap(function()
            load.load('quicker')
          end)
        )
      end,
    },
  },

  {
    src = 'https://github.com/folke/which-key.nvim',
    data = {
      load = function()
        local load = require('utils.load')

        load.on_events(
          'UIEnter',
          'which-key',
          vim.schedule_wrap(function()
            load.load('which-key')
          end)
        )
      end,
    },
  },

  {
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
        desc = 'Toggle focus between opencode and last window',
      },
    },
  },
}
