return {
  {
    'ibhagwan/fzf-lua',
    cmd = 'FzfLua',
    keys = {
      { '<Leader>.', desc = 'Find files' },
      { "<Leader>'", desc = 'Resume last picker' },
      { '<Leader>,', desc = 'Find buffers' },
      { '<Leader>/', desc = 'Grep' },
      { '<Leader>?', desc = 'Find help files' },
      { '<Leader>*', mode = { 'n', 'x' }, desc = 'Grep word under cursor' },
      { '<Leader>#', mode = { 'n', 'x' }, desc = 'Grep word under cursor' },
      { '<Leader>"', desc = 'Find registers' },
      { '<Leader>:', desc = 'Find commands' },
      { '<Leader>F', desc = 'Find all available pickers' },
      { '<Leader>o', desc = 'Find oldfiles' },
      { '<Leader>-', desc = 'Find lines in buffer' },
      { '<Leader>=', desc = 'Find lines across buffers' },
      { '<Leader>R', desc = 'Find symbol locations' },
      { '<Leader>f"', desc = 'Find registers' },
      { '<Leader>f*', mode = { 'n', 'x' }, desc = 'Grep word under cursor' },
      { '<Leader>f#', mode = { 'n', 'x' }, desc = 'Grep word under cursor' },
      { '<Leader>f:', desc = 'Find commands' },
      { '<Leader>f/', desc = 'Grep' },
      { '<Leader>fH', desc = 'Find highlights' },
      { "<Leader>f'", desc = 'Resume last picker' },
      { '<Leader>fA', desc = 'Find autocmds' },
      { '<Leader>fb', desc = 'Find buffers' },
      { '<Leader>fp', desc = 'Find tabpages' },
      { '<Leader>ft', desc = 'Find tags' },
      { '<Leader>fc', desc = 'Find changes' },
      { '<Leader>fd', desc = 'Find document diagnostics' },
      { '<Leader>fD', desc = 'Find workspace diagnostics' },
      { '<Leader>ff', desc = 'Find files' },
      { '<Leader>fa', desc = 'Find args' },
      { '<Leader>fl', desc = 'Find location list' },
      { '<Leader>fq', desc = 'Find quickfix list' },
      { '<Leader>fL', desc = 'Find location list stack' },
      { '<Leader>fQ', desc = 'Find quickfix stack' },
      { '<Leader>fgt', desc = 'Find git tags' },
      { '<Leader>fgs', desc = 'Find git stash' },
      { '<Leader>fgg', desc = 'Find git status' },
      { '<Leader>fgc', desc = 'Find git commits' },
      { '<Leader>fgl', desc = 'Find git buffer commits' },
      { '<Leader>fgb', desc = 'Find git branches' },
      { '<Leader>fgB', desc = 'Find git blame' },
      { '<Leader>fh', desc = 'Find help files' },
      { '<Leader>fk', desc = 'Find keymaps' },
      { '<Leader>f-', desc = 'Find lines in buffer' },
      { '<Leader>f=', desc = 'Find lines across buffers' },
      { '<Leader>fm', desc = 'Find marks' },
      { '<Leader>fo', desc = 'Find oldfiles' },
      { '<Leader>fS', desc = 'Find lsp symbols or treesitter nodes' },
      { '<Leader>fsa', desc = 'Find code actions' },
      { '<Leader>fsd', desc = 'Find symbol definitions' },
      { '<Leader>fsD', desc = 'Find symbol declarations' },
      { '<Leader>fs<C-d>', desc = 'Find symbol type definitions' },
      { '<Leader>fss', desc = 'Find symbol in current document' },
      { '<Leader>fsS', desc = 'Find symbol in whole workspace' },
      { '<Leader>fsi', desc = 'Find symbol implementations' },
      { '<Leader>fs<', desc = 'Find symbol incoming calls' },
      { '<Leader>fs>', desc = 'Find symbol outgoing calls' },
      { '<Leader>fsr', desc = 'Find symbol references' },
      { '<Leader>fsR', desc = 'Find symbol locations' },
      { '<Leader>fF', desc = 'Find all available pickers' },
    },
    event = 'LspAttach',
    build = 'fzf --version',
    init = function()
      -- Disable fzf's default vim plugin
      vim.g.loaded_fzf = 1

      ---@diagnostic disable-next-line: duplicate-set-field
      vim.ui.select = function(...)
        local fzf_ui = require('fzf-lua.providers.ui_select')
        -- Register fzf as custom `vim.ui.select()` function if not yet
        -- registered
        if not fzf_ui.is_registered() then
          local _ui_select = fzf_ui.ui_select
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
              and vim.fn.substitute(opts.prompt, ':\\?\\s*$', ':\xc2\xa0', '')
            _ui_select(items, opts, on_choice)
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
            return {
              winopts = {
                split = string.format(
                  [[
                    let tabpage_win_list = nvim_tabpage_list_wins(0) |
                    \ call v:lua.require'utils.win'.saveheights(tabpage_win_list) |
                    \ call v:lua.require'utils.win'.saveviews(tabpage_win_list) |
                    \ unlet tabpage_win_list |
                    \ let g:_fzf_vim_lines = &lines |
                    \ let g:_fzf_leave_win = win_getid(winnr()) |
                    \ let g:_fzf_splitkeep = &splitkeep | let &splitkeep = "topline" |
                    \ let g:_fzf_cmdheight = &cmdheight | let &cmdheight = 0 |
                    \ let g:_fzf_laststatus = &laststatus | let &laststatus = 0 |
                    \ botright %dnew |
                    \ let w:winbar_no_attach = v:true |
                    \ setlocal bt=nofile bh=wipe nobl noswf wfh
                  ]],
                  math.min(
                    10 + vim.go.ch + (vim.go.ls == 0 and 0 or 1),
                    #items + 1
                  )
                ),
              },
            }
          end)
        end
        vim.ui.select(...)
      end
    end,
    config = function()
      require('configs.fzf-lua')
    end,
  },

  {
    'lewis6991/gitsigns.nvim',
    event = 'BufReadPre',
    dependencies = 'nvim-lua/plenary.nvim',
    config = function()
      require('configs.gitsigns')
    end,
  },

  {
    'tpope/vim-fugitive',
    cmd = {
      'G',
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
    keys = { { '<Leader>gL', desc = 'Open git log' } },
    event = { 'BufNew', 'BufWritePost', 'BufReadPre' },
    dependencies = {
      -- Enable :GBrowse command in GitHub/Gitlab repos
      'tpope/vim-rhubarb',
      'shumphrey/fugitive-gitlab.vim',
    },
    config = function()
      require('configs.vim-fugitive')
    end,
  },

  {
    'NvChad/nvim-colorizer.lua',
    event = {
      'BufNew',
      'BufRead',
      'BufWritePost',
      'TextChanged',
      'TextChangedI',
      'StdinReadPre',
    },
    config = function()
      require('configs.nvim-colorizer')
    end,
  },

  {
    'stevearc/oil.nvim',
    cmd = 'Oil',
    init = function() -- Load oil on startup only when editing a directory
      vim.g.loaded_fzf_file_explorer = 0
      vim.g.loaded_netrw = 0
      vim.g.loaded_netrwPlugin = 0
      vim.api.nvim_create_autocmd('BufEnter', {
        nested = true,
        -- Use `vim.schedule()` here to wait session to be loaded and
        -- buffer attributes, e.g. buffer name, to be updated before
        -- checking if the buffer is a directory buffer
        callback = vim.schedule_wrap(function(info)
          local buf = info.buf
          local id = info.id

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

          if not vim.api.nvim_buf_is_valid(buf) then
            return
          end

          vim.api.nvim_buf_call(
            buf,
            -- Use `vim.schedule_wrap` to make it work for `:e .` after session
            -- load
            vim.schedule_wrap(function()
              -- Use `pcall()` to suppress error when opening cmdwin with the
              -- cursor is inside a modified lua or python buffer with no
              -- corresponding file. This does not happen with other filetypes,
              -- e.g. c/cpp or tex files
              -- It seems that the error is caused by lua/python's lsp servers
              -- making an hidden buffer with bufname '/' (use `:ls!` to show
              -- the hidden buffers) because disabling lsp server configs in
              -- `after/ftplugin/lua/lsp.lua` and `after/ftplugin/python/lsp.lua`
              -- prevents this error and the hidden '/' buffer is gone
              pcall(vim.cmd.edit, {
                bang = true,
                mods = { keepjumps = true },
              })
            end)
          )
        end),
      })
    end,
    config = function()
      require('configs.oil')
    end,
  },

  {
    'folke/which-key.nvim',
    event = 'VeryLazy',
    config = function()
      require('configs.which-key')
    end,
  },
}
