return {
  {
    'ibhagwan/fzf-lua',
    cmd = {
      'FzfLua',
      'FZF',
      'Ls',
      'Args',
      'Tabs',
      'Tags',
      'Files',
      'Marks',
      'Jumps',
      'Autocmd',
      'Buffers',
      'Changes',
      'Display',
      'Oldfiles',
      'Registers',
      'Highlight',
    },
    keys = {
      '<Leader>.',
      '<Leader>,',
      '<Leader>:',
      '<Leader>/',
      '<Leader>?',
      '<Leader>"',
      '<Leader>o',
      "<Leader>'",
      '<Leader>-',
      '<Leader>=',
      '<Leader>s',
      '<Leader>R',
      '<Leader>F',
      '<Leader>f',
      '<Leader>ff',
      { '<Leader>*', mode = { 'n', 'x' } },
      { '<Leader>#', mode = { 'n', 'x' } },
    },
    event = 'LspAttach',
    build = 'fzf --version',
    init = vim.schedule_wrap(function()
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
      vim.api.nvim_create_autocmd('CmdlineEnter', {
        group = vim.api.nvim_create_augroup('FzfLuaCreateCmdAbbr', {}),
        once = true,
        callback = function(info)
          local keymap = require('utils.keymap')
          keymap.command_abbrev('ls', 'Ls')
          keymap.command_abbrev('tabs', 'Tabs')
          keymap.command_abbrev('tags', 'Tags')
          keymap.command_abbrev('files', 'Files')
          keymap.command_abbrev('marks', 'Marks')
          keymap.command_abbrev('buffers', 'Buffers')
          keymap.command_abbrev('changes', 'Changes')
          keymap.command_abbrev({ 'ar', 'args' }, 'Args')
          keymap.command_abbrev({ 'ju', 'jumps' }, 'Jumps')
          keymap.command_abbrev({ 'au', 'autocmd' }, 'Autocmd')
          keymap.command_abbrev({ 'di', 'display' }, 'Display')
          keymap.command_abbrev({ 'o', 'oldfiles' }, 'Oldfiles')
          keymap.command_abbrev({ 'hi', 'highlight' }, 'Highlight')
          keymap.command_abbrev({ 'reg', 'registers' }, 'Registers')
          vim.api.nvim_del_augroup_by_id(info.group)
          return true
        end,
      })
    end),
    config = function()
      require('configs.fzf-lua')
    end,
  },

  {
    'willothy/flatten.nvim',
    event = 'BufReadPre',
    config = function()
      require('configs.flatten')
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
    keys = { '<Leader>gL' },
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
    'akinsho/git-conflict.nvim',
    event = 'BufReadPre',
    config = function()
      require('configs.git-conflict')
    end,
  },

  {
    'NvChad/nvim-colorizer.lua',
    enabled = vim.g.has_display,
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
      vim.g.loaded_fzf_file_explorer = 1
      vim.g.loaded_netrw = 1
      vim.g.loaded_netrwPlugin = 1
      vim.api.nvim_create_autocmd('BufWinEnter', {
        nested = true,
        callback = function(info)
          local dirbuf_found
          -- Check each buffer to see if it is a directory buffer,
          -- if so, open oil in that buffer
          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            -- Use `vim.schedule()` here to wait session to be loaded and
            -- buffer attributes, e.g. buffer name, to be updated before
            -- checking if the buffer is a directory buffer
            vim.schedule(function()
              if not vim.api.nvim_buf_is_valid(buf) then
                return
              end

              local bufname = vim.api.nvim_buf_get_name(buf)
              if
                not vim.startswith(bufname, 'oil://')
                and (vim.uv.fs_stat(bufname) or {}).type ~= 'directory'
              then
                return
              end

              if not dirbuf_found then
                dirbuf_found = true
                pcall(require, 'oil')
                pcall(vim.api.nvim_del_autocmd, info.id)
              end

              if not vim.api.nvim_buf_is_valid(buf) then
                return
              end
              vim.api.nvim_buf_call(buf, function()
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
            end)
          end
        end,
      })
    end,
    config = function()
      require('configs.oil')
    end,
  },
}
