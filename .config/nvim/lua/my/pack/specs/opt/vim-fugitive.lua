---@type my.pack.spec
return {
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
      'D',
      'Dot',
      'Dread',
      'Dedit',
      'Dwrite',
      'Ddiffsplit',
      'Dhdiffsplit',
      'Dvdiffsplit',
      'DMove',
      'DRename',
      'DRemove',
      'DUnlink',
      'DDelete',
    },
    keys = {
      { lhs = '<Leader>gg', opts = { desc = 'Git summary' } },
      { lhs = '<Leader>gw', opts = { desc = 'Git show latest commit' } },
      { lhs = '<Leader>gb', opts = { desc = 'Git list local branches' } },
      { lhs = '<Leader>gc', opts = { desc = 'Git commit' } },
      { lhs = '<Leader>gP', opts = { desc = 'Git push' } },
      {
        lhs = '<Leader>gL',
        opts = { desc = 'Git log entire repo' },
      },
      {
        lhs = '<Leader>g<Space>',
        opts = { desc = 'Populate cmdline with ":Git"' },
      },
    },
    events = { 'BufNew', 'BufWritePost', 'BufReadPre' },
    deps = {
      -- Enable :GBrowse command in GitHub/Gitlab repos
      'https://github.com/tpope/vim-rhubarb',
      {
        src = 'https://github.com/shumphrey/fugitive-gitlab.vim',
        data = {
          postload = function()
            -- Alibaba's GitLab-compatible service uses a different web host and
            -- omits the `/-/` component found in current GitLab URLs.
            vim.g.fugitive_gitlab_domains = {
              ['gitlab.alibaba-inc.com'] = 'https://code.alibaba-inc.com',
            }
            vim.g.fugitive_gitlab_oldstyle_urls = true
          end,
        },
      },
    },
    postload = function()
      vim.cmd([[
        " By default open the fugitive window in a split below current window instead
        " of at the bottom of screen, preventing it from being squeezed by windows
        " with `winfixheight` set
        command! -bang -nargs=? -range=-1 -complete=customlist,fugitive#Complete G   exe fugitive#Command(<line1>, <count>, +"<range>", <bang>0, "<mods>" . " belowright", <q-args>)
        command! -bang -nargs=? -range=-1 -complete=customlist,fugitive#Complete Git exe fugitive#Command(<line1>, <count>, +"<range>", <bang>0, "<mods>" . " belowright", <q-args>)

        " Override the default fugitive commands to save the previous buffer
        " before opening the log window.
        command! -bang -nargs=? -range=-1 -complete=customlist,fugitive#LogComplete Gclog let g:fugitive_prevbuf=bufnr() | exe fugitive#LogCommand(<line1>,<count>,+"<range>",<bang>0,"<mods>",<q-args>, "c")
        command! -bang -nargs=? -range=-1 -complete=customlist,fugitive#LogComplete GcLog let g:fugitive_prevbuf=bufnr() | exe fugitive#LogCommand(<line1>,<count>,+"<range>",<bang>0,"<mods>",<q-args>, "c")
        command! -bang -nargs=? -range=-1 -complete=customlist,fugitive#LogComplete Gllog let g:fugitive_prevbuf=bufnr() | exe fugitive#LogCommand(<line1>,<count>,+"<range>",<bang>0,"<mods>",<q-args>, "l")
        command! -bang -nargs=? -range=-1 -complete=customlist,fugitive#LogComplete GlLog let g:fugitive_prevbuf=bufnr() | exe fugitive#LogCommand(<line1>,<count>,+"<range>",<bang>0,"<mods>",<q-args>, "l")
      ]])

      ---Resolve the commit of a git command output buffer, e.g.
      ---Returns the full sha of `HEAD~1` for command `:Git show --stat HEAD~1`,
      ---or the full sha of `HEAD` for `:Git log`, by reversely traversing
      ---the args and try to resolve them to a git commit one-by-one.
      ---@param fugitive_result table temp state returned by `FugitiveResult()`, which contains the git command that produced the given git temp buffer
      ---@return string? commit full sha of the commit shown in the buffer
      local function resolve_fugitive_result_commit(fugitive_result)
        if type(fugitive_result.args) ~= 'table' then
          return
        end
        -- Candidate args, `HEAD` as last resort
        local args = { 'HEAD' }
        for _, arg in ipairs(fugitive_result.args) do
          if arg == '--' then
            break
          end
          if not vim.startswith(arg, '-') then
            table.insert(args, arg)
          end
        end
        for arg in vim.iter(args):rev() do
          local commit = vim.fn.FugitiveExecute({
            'rev-parse',
            '--verify',
            '--quiet',
            ('%s^{commit}'):format(arg),
            '--',
          }, fugitive_result.git_dir).stdout[1]
          -- Failed `rev-parse` outputs nothing, i.e. `stdout` is `{''}`
          if commit and commit ~= '' then
            return commit
          end
        end
      end

      ---Resolve the object under the cursor in a git command output buffer
      ---@param fugitive_result table temp state returned by `FugitiveResult()`
      ---@return string? object fugitive object under the cursor
      local function resolve_fugitive_result_cursor_object(fugitive_result)
        if fugitive_result.filetype ~= 'git' then
          return
        end
        local cfile = vim.fn['fugitive#Cfile']()
        if not vim.startswith(cfile, 'fugitive://') then
          return
        end
        local object = vim.fn['fugitive#Object'](cfile)
        if object ~= '' then
          return object
        end
      end

      ---Resolve the object under the cursor, then fall back to the result's
      ---commit
      ---@param fugitive_result table temp state returned by `FugitiveResult()`
      ---@param fallback? string previously resolved fallback commit
      ---@return string? object fugitive object under the cursor
      local function resolve_fugitive_result_object(fugitive_result, fallback)
        return resolve_fugitive_result_cursor_object(fugitive_result)
          or fallback
          or resolve_fugitive_result_commit(fugitive_result)
      end

      -- Make `:GBrowse!` copy the link to the object under the cursor in git
      -- command output buffers, falling back to the command's exact commit
      vim.api.nvim_create_user_command('GBrowse', function(args)
        local obj = args.args
        if obj == '' then
          local result = vim.fn.FugitiveResult(vim.api.nvim_get_current_buf())
          obj = resolve_fugitive_result_object(result) or ''
        end
        local ret = vim.fn['fugitive#BrowseCommand'](
          args.line1,
          args.count,
          args.range,
          args.bang and 1 or 0,
          args.mods,
          obj
        )
        if type(ret) ~= 'string' or ret == '' then
          return
        end
        -- `fugitive#BrowseCommand()` returns an ex command to execute;
        -- echo `echoerr` messages cleanly instead of raising a Lua error
        local err = ret:match('^echoerr%s+(.+)$')
        if err then
          vim.api.nvim_echo({ { vim.fn.eval(err), 'ErrorMsg' } }, true, {})
          return
        end
        vim.cmd(ret)
      end, {
        bang = true,
        bar = true,
        range = -1,
        nargs = '*',
        complete = 'customlist,fugitive#CompleteObject',
        desc = 'Browse the current file, blob, tree, commit, or tag on the remote',
      })

      ---Open Git command output in a scratch buffer
      ---@param result table
      ---@param win integer
      ---@param mods vim.api.keyset.cmd_mods
      ---@param command string
      local function open_git_output(result, win, mods, command)
        if result.exit_status ~= 0 then
          local message = table.concat(result.stderr or {}, '\n')
          vim.notify(
            ('[vim-fugitive] %s failed: %s'):format(command, message),
            vim.log.levels.ERROR
          )
          return
        end

        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(buf, ('%s://%d'):format(command, buf))
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, result.stdout or {})
        vim.api.nvim_buf_call(buf, function()
          vim.bo.buftype = 'nowrite'
          vim.bo.filetype = 'git'
          vim.bo.modifiable = false
          vim.bo.readonly = true
          vim.b.git_dir = result.git_dir
        end)

        require('my.utils.win').open_with_mods(buf, mods, win)
      end

      ---Command callback to search for a selected literal block across all Git
      ---commits
      ---@param args vim.api.keyset.create_user_command.command_args
      local function git_gr_cmd(args)
        local lines =
          vim.api.nvim_buf_get_lines(0, args.line1 - 1, args.line2, false)
        local has_nonempty_line = false

        for _, line in ipairs(lines) do
          if line ~= '' then
            has_nonempty_line = true
            break
          end
        end

        if not has_nonempty_line then
          vim.notify(
            '[vim-fugutive] no non-empty lines to grep',
            vim.log.levels.WARN
          )
          return
        end

        local pattern = table.concat(lines, '\n')
        local source_buf = vim.api.nvim_get_current_buf()
        local win = vim.api.nvim_get_current_win()
        vim.fn.FugitiveExecute(
          {
            'log',
            '--all',
            '-p',
            '--color=never',
            '-S' .. pattern,
            '--format=@@@ %h %s',
            '--',
          },
          source_buf,
          vim.schedule_wrap(function(result)
            open_git_output(result, win, args.smods, 'Gitgr')
          end)
        )
      end

      vim.api.nvim_create_user_command('Gitgr', git_gr_cmd, {
        desc = 'Search selected literal block across all Git commits',
        range = true,
      })
      vim.api.nvim_create_user_command('Ggr', git_gr_cmd, {
        desc = 'Alias for Gitgr',
        range = true,
      })

      ---Show the line log for the selected range in the current file
      ---@param args vim.api.keyset.create_user_command.command_args
      local function git_ll_cmd(args)
        local source_buf = vim.api.nvim_get_current_buf()
        local path = vim.fn.FugitivePath(
          vim.api.nvim_buf_get_name(source_buf),
          '',
          source_buf
        )
        if path == '' then
          vim.notify(
            '[vim-fugitive] current buffer is not a file in a Git repository',
            vim.log.levels.WARN
          )
          return
        end

        local line_range = ('%d,%d:%s'):format(args.line1, args.line2, path)
        local win = vim.api.nvim_get_current_win()
        vim.fn.FugitiveExecute(
          { 'll', line_range },
          source_buf,
          vim.schedule_wrap(function(result)
            open_git_output(result, win, args.smods, 'Gll')
          end)
        )
      end

      vim.api.nvim_create_user_command('Gitll', git_ll_cmd, {
        desc = 'Show line log for selected range',
        range = true,
      })
      vim.api.nvim_create_user_command('Gll', git_ll_cmd, {
        desc = 'Alias for Gitll',
        range = true,
      })

      -- stylua: ignore start
      vim.keymap.set('n', '<Leader>gg',       '<Cmd>Git<CR>',                                  { desc = 'Git summary' })
      vim.keymap.set('n', '<Leader>gd',       '<Cmd>Gdiff<CR>',                                { desc = 'Git diff current file' })
      vim.keymap.set('n', '<Leader>gw',       '<Cmd>Git show<CR>',                             { desc = 'Git show latest commit' })
      vim.keymap.set('n', '<Leader>gb',       '<Cmd>Git branch<CR><Cmd>call search("^*")<CR>', { desc = 'Git list local branches' })
      vim.keymap.set('n', '<Leader>gc',       '<Cmd>Git commit<CR>',                           { desc = 'Git commit' })
      vim.keymap.set('n', '<Leader>gP',       '<Cmd>Git push<CR>',                             { desc = 'Git push' })
      vim.keymap.set('n', '<Leader>gD',       '<Cmd>Git diff<CR>',                             { desc = 'Git diff entire repo' })
      vim.keymap.set('n', '<Leader>gB',       '<Cmd>Git blame<CR>',                            { desc = 'Git blame current file' })
      vim.keymap.set('n', '<Leader>gl',       '<Cmd>Git log -100 --oneline --follow -- %<CR>', { desc = 'Git log current file' })
      vim.keymap.set('n', '<Leader>gL',       '<Cmd>Git log -100 --oneline --graph<CR>',       { desc = 'Git log entire repo' })
      vim.keymap.set('n', '<Leader>g<Space>', ':Git<Space>',                                   { desc = 'Populate cmdline with ":Git"' })
      -- stylua: ignore end

      local group = vim.api.nvim_create_augroup('my.fugitive', {})

      vim.api.nvim_create_autocmd('User', {
        pattern = 'FugitiveIndex',
        group = group,
        callback = function(args)
          vim.keymap.set({ 'n', 'x' }, '[g', '[c', {
            desc = 'Go to previous hunk',
            buffer = args.buf,
            remap = true,
          })
          vim.keymap.set({ 'n', 'x' }, ']g', ']c', {
            desc = 'Go to next hunk',
            buffer = args.buf,
            remap = true,
          })
        end,
      })

      vim.api.nvim_create_autocmd('User', {
        pattern = 'FugitiveObject',
        group = group,
        callback = function()
          -- stylua: ignore start
          local goto_next = [[<Cmd>silent! exe "if get(getloclist(0, {'winid':''}), 'winid', 0) | exe v:count.'lne' | else | exe v:count.'cn' | endif"<CR>]]
          local goto_prev = [[<Cmd>silent! exe "if get(getloclist(0, {'winid':''}), 'winid', 0) | exe v:count.'lpr' | else | exe v:count.'cp' | endif"<CR>]]
          -- stylua: ignore end
          vim.keymap.set('n', '<C-n>', goto_next, { buffer = true })
          vim.keymap.set('n', '<C-p>', goto_prev, { buffer = true })
          vim.keymap.set('n', '<C-j>', goto_next, { buffer = true })
          vim.keymap.set('n', '<C-k>', goto_prev, { buffer = true })
          vim.keymap.set('n', '<C-^>', function()
            if vim.g.fugitive_prevbuf then
              vim.cmd.cclose()
              vim.cmd.lclose()
              vim.cmd.buffer(vim.g.fugitive_prevbuf)
              vim.g.fugitive_prevbuf = nil
              vim.cmd.bw({ '#', bang = true, mods = { emsg_silent = true } })
            end
          end, { buffer = true })
        end,
      })

      vim.api.nvim_create_autocmd('BufEnter', {
        desc = 'Ensure that fugitive buffers are not listed and are wiped out after hidden.',
        group = group,
        pattern = 'fugitive://*',
        callback = function(args)
          vim.bo[args.buf].buflisted = false
        end,
      })

      vim.api.nvim_create_autocmd('FileType', {
        desc = 'Set buffer-local options for fugitive buffers.',
        group = group,
        pattern = 'fugitive',
        callback = function()
          vim.opt_local.winbar = nil
          vim.opt_local.signcolumn = 'no'
          vim.opt_local.number = false
          vim.opt_local.relativenumber = false
        end,
      })

      vim.api.nvim_create_autocmd('FileType', {
        desc = 'Set buffer-local options for fugitive blame buffers.',
        group = group,
        pattern = 'fugitiveblame',
        callback = function()
          local win_alt = vim.fn.win_getid(vim.fn.winnr('#'))
          vim.opt_local.winbar = vim.api.nvim_win_is_valid(win_alt)
              and vim.wo[win_alt].winbar ~= ''
              and ' '
            or ''

          vim.opt_local.number = false
          vim.opt_local.signcolumn = 'no'
          vim.opt_local.relativenumber = false
        end,
      })

      -- Turn `:Git show [rev]` buffers into real fugitive object buffers so
      -- that fugitive operations (`y<C-G>`, `:GBrowse`, etc.) work in them;
      -- shim `y<C-G>` for other output buffers centered on a commit
      vim.api.nvim_create_autocmd('FileType', {
        pattern = 'git',
        group = group,
        -- Let the `edit` below trigger nested buffer read autocmds
        nested = true,
        callback = function(args)
          local result = vim.fn.FugitiveResult(args.buf)
          local commit = resolve_fugitive_result_commit(result)
          if not commit then
            return
          end
          local cmd_args = result.args
          -- Only redirect plain `:Git show` and `:Git show <rev>` where the
          -- shown object is a commit or a blob, whose object buffers show
          -- the same content as the command output
          if
            cmd_args[1] == 'show'
            and (
              #cmd_args == 1
              or (#cmd_args == 2 and cmd_args[2]:sub(1, 1) ~= '-')
            )
          then
            local rev = #cmd_args == 2 and cmd_args[2] or 'HEAD'
            local obj_type = vim.fn.FugitiveExecute({
              'cat-file',
              '-t',
              rev,
            }, result.git_dir).stdout[1]
            if obj_type == 'commit' or obj_type == 'blob' then
              -- Use the explicit fugitive URL instead of `:Gedit` since
              -- the temp buffer's `b:git_dir` may not agree with
              -- `result.git_dir`
              vim.cmd.edit(
                vim.fn.fnameescape(
                  vim.fn['fugitive#Find'](rev, result.git_dir)
                )
              )
              -- Delete the temp buffer after the FileType autocmds finish,
              -- deleting it right away breaks other FileType autocmds
              vim.schedule(function()
                if vim.api.nvim_buf_is_valid(args.buf) then
                  vim.api.nvim_buf_delete(args.buf, {})
                end
              end)
              return
            end
          end
          -- Other commit-centered buffers (e.g. `:Git show --stat`,
          -- `:Git stash show`) have no object buffer equivalent
          local function resolve_object()
            return resolve_fugitive_result_object(result, commit)
          end
          local function yank_object()
            vim.fn.setreg(vim.v.register, resolve_object())
          end
          vim.keymap.set('n', '<Plug>fugitive:y<C-G>', yank_object, {
            buffer = args.buf,
          })
          vim.keymap.set('n', 'y<C-G>', '<Plug>fugitive:y<C-G>', {
            buffer = args.buf,
            desc = 'Yank object under cursor',
            remap = true,
          })
          vim.keymap.set('c', '<C-R><C-G>', function()
            return vim.fn.fnameescape(resolve_object())
          end, {
            buffer = args.buf,
            desc = 'Insert object under cursor',
            expr = true,
            replace_keycodes = false,
          })
        end,
      })

      -- Configs for dotfiles bare repo

      ---Detect and set git dir for given buffer, fallback to dotfiles bare
      ---repo if current file is not in a regular git repo
      ---@param buf? integer
      local function detect(buf)
        buf = vim._resolve_bufnr(buf)
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        -- Buffer already in a valid local git dir
        -- Re-check git dir if the buffer has the dotfiles bare repo as git
        -- dir as a new local git dir is likely to be created in the containing
        -- dir of the buffer later
        if
          vim.b[buf].git_dir
          and vim.b[buf].git_dir ~= ''
          and vim.b[buf].git_dir ~= vim.env.DOT_DIR
        then
          return
        end
        vim.b[buf].git_dir = nil
        -- Normalize `oil://...` buffers
        local buf_name = vim.api.nvim_buf_get_name(buf):gsub('^%S+://', '', 1)
        local buf_path = buf_name ~= '' and buf_name or vim.fn.getcwd(0)
        vim.api.nvim_buf_call(buf, function()
          -- `FugitiveDetect()` will fail to detect git dir under current
          -- working directory in the first empty buffer
          -- Workaround: pass current cwd to it
          vim.fn.FugitiveDetect(buf_path)
        end)
        if vim.b[buf].git_dir and vim.b[buf].git_dir ~= '' then
          return
        end
        -- Fallback to dotfiles bare repo
        -- https://github.com/tpope/vim-fugitive/issues/1796#issuecomment-900725518
        vim.api.nvim_buf_call(buf, function()
          vim.fn.FugitiveDetect(vim.env.DOT_DIR)
        end)
      end

      detect()

      vim.api.nvim_create_autocmd({ 'BufEnter', 'FileType' }, {
        desc = 'Make fugitive aware of bare repo for dotfiles.',
        group = group,
        callback = function(args)
          detect(args.buf)
        end,
      })
      vim.api.nvim_create_autocmd('DirChanged', {
        desc = 'Re-detect current git dir on buf dir changed.',
        group = group,
        callback = function(args)
          detect(args.buf)
        end,
      })

      -- Custom commands to manage dotfiles bare repo, adapted from:
      -- https://github.com/tpope/vim-fugitive/issues/2191#issuecomment-1636692107

      ---Create corresponding commands for dotfiles bare repo
      ---@param cmd string command name
      ---@param fugitive_cmd string corresponding fugitive command
      ---@param opts? vim.api.keyset.user_command
      local function create_dotfiles_cmd(cmd, fugitive_cmd, opts)
        opts = opts or {}

        ---@param a vim.api.keyset.create_user_command.command_args
        vim.api.nvim_create_user_command(cmd, function(a)
          local buf_git_dir = vim.b.git_dir
          local env_git_dir = vim.env.GIT_DIR
          local env_git_work_tree = vim.env.GIT_WORK_TREE

          vim.b.git_dir = vim.env.DOT_DIR
          vim.env.GIT_DIR = vim.env.DOT_DIR
          vim.env.GIT_WORK_TREE = vim.uv.os_homedir()

          vim.cmd[fugitive_cmd]({
            args = a.fargs,
            mods = a.smods,
            bang = a.bang,
            reg = opts.register and a.reg,
            range = opts.range and { a.line1, a.line2 },
            count = opts.count and a.count,
          })

          vim.b.git_dir = buf_git_dir
          vim.env.GIT_DIR = env_git_dir
          vim.env.GIT_WORK_TREE = env_git_work_tree
        end, opts)
      end

      for _, cmd in ipairs({ 'D', 'Dot' }) do
        create_dotfiles_cmd(cmd, 'Git', {
          nargs = '?',
          ---@param arglead string leading portion of the argument being completed
          ---@param cmdline string the entire command line
          ---@param cursorpos integer cursor position in the command line
          ---@return string[] completion completion results
          complete = function(arglead, cmdline, cursorpos)
            return vim.fn['fugitive#Complete'](
              arglead,
              cmdline,
              cursorpos,
              { git_dir = vim.env.DOT_DIR }
            )
          end,
        })
      end
      -- stylua: ignore start
      create_dotfiles_cmd('Dread',       'Gread',       { nargs = '*', complete = vim.fn['fugitive#ReadComplete'] })
      create_dotfiles_cmd('Dedit',       'Gedit',       { nargs = '*', complete = vim.fn['fugitive#EditComplete'] })
      create_dotfiles_cmd('Dwrite',      'Gwrite',      { nargs = '*', complete = vim.fn['fugitive#EditComplete'] })
      create_dotfiles_cmd('Ddiffsplit',  'Gdiffsplit',  { nargs = '*', complete = vim.fn['fugitive#EditComplete'] })
      create_dotfiles_cmd('Dhdiffsplit', 'Ghdiffsplit', { nargs = '*', complete = vim.fn['fugitive#EditComplete'] })
      create_dotfiles_cmd('Dvdiffsplit', 'Gvdiffsplit', { nargs = '*', complete = vim.fn['fugitive#EditComplete'] })
      create_dotfiles_cmd('DMove',       'GMove',       { nargs = 1,   complete = vim.fn['fugitive#CompleteObject'] })
      create_dotfiles_cmd('DRename',     'GRename',     { nargs = 1,   complete = vim.fn['fugitive#RenameComplete'] })
      create_dotfiles_cmd('DRemove',     'GRemove',     { nargs = 0 })
      create_dotfiles_cmd('DUnlink',     'GUnlink',     { nargs = 0 })
      create_dotfiles_cmd('DDelete',     'GDelete',     { nargs = 0 })
      -- stylua: ignore end
    end,
  },
}
