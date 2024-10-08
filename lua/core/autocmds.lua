local autocmd = vim.api.nvim_create_autocmd
local groupid = vim.api.nvim_create_augroup

---@param group string
---@vararg { [1]: string|string[], [2]: vim.api.keyset.create_autocmd }
---@return nil
local function augroup(group, ...)
  local id = groupid(group, {})
  for _, a in ipairs({ ... }) do
    a[2].group = id
    autocmd(unpack(a))
  end
end

augroup('BigFileSettings', {
  'BufReadPre',
  {
    desc = 'Set settings for large files.',
    callback = function(info)
      vim.b.bigfile = false
      local stat = vim.uv.fs_stat(info.match)
      if stat and stat.size > 1048576 then
        vim.b.bigfile = true
        vim.opt_local.spell = false
        vim.opt_local.swapfile = false
        vim.opt_local.undofile = false
        vim.opt_local.breakindent = false
        vim.opt_local.colorcolumn = ''
        vim.opt_local.statuscolumn = ''
        vim.opt_local.signcolumn = 'no'
        vim.opt_local.foldcolumn = '0'
        vim.opt_local.winbar = ''
        vim.opt_local.syntax = ''
        autocmd('BufReadPost', {
          once = true,
          buffer = info.buf,
          callback = function()
            vim.opt_local.syntax = ''
            return true
          end,
        })
      end
    end,
  },
})

augroup('YankHighlight', {
  'TextYankPost',
  {
    desc = 'Highlight the selection on yank.',
    callback = function()
      pcall(vim.highlight.on_yank, {
        higroup = 'Visual',
        timeout = 200,
      })
    end,
  },
})

augroup('Autosave', {
  { 'BufLeave', 'WinLeave', 'FocusLost' },
  {
    nested = true,
    desc = 'Autosave on focus change.',
    callback = function(info)
      -- Don't auto-save non-file buffers
      if (vim.uv.fs_stat(info.file) or {}).type ~= 'file' then
        return
      end
      vim.cmd.update({
        mods = { emsg_silent = true },
      })
    end,
  },
})

augroup('WinCloseJmp', {
  'WinClosed',
  {
    nested = true,
    desc = 'Jump to last accessed window on closing the current one.',
    command = "if expand('<amatch>') == win_getid() | wincmd p | endif",
  },
})

augroup('LastPosJmp', {
  'BufReadPost',
  {
    desc = 'Last position jump.',
    callback = function(info)
      local ft = vim.bo[info.buf].ft
      -- don't apply to git messages
      if ft ~= 'gitcommit' and ft ~= 'gitrebase' then
        vim.cmd.normal({
          'g`"zvzz',
          bang = true,
          mods = { emsg_silent = true },
        })
      end
    end,
  },
})

augroup('AutoCwd', {
  'LspAttach',
  {
    desc = 'Record LSP root directories in `vim.g._lsp_root_dirs`.',
    callback = function(info)
      local client = vim.lsp.get_client_by_id(info.data.client_id)
      local root_dir = client and client.config and client.config.root_dir
      if
        not root_dir
        or root_dir == vim.fs.normalize('~')
        or root_dir == vim.fs.dirname(root_dir)
      then
        return
      end

      -- Keep only shortest root dir in `vim.g._lsp_root_dirs`,
      -- e.g. if we have `~/project` and `~/project/subdir`, keep only
      -- `~/project`
      local lsp_root_dirs = vim.g._lsp_root_dirs or {}
      for i, dir in ipairs(lsp_root_dirs) do
        -- If the new root dir is a subdirectory of an existing root dir,
        -- return early and don't add it
        if require('utils.fs').contains(dir, root_dir) then
          return
        end
        if vim.startswith(dir, root_dir) then
          table.remove(lsp_root_dirs, i)
        end
      end
      table.insert(lsp_root_dirs, root_dir)
      vim.g._lsp_root_dirs = lsp_root_dirs

      -- Execute BufWinEnter event on current buffer to trigger cwd change
      vim.api.nvim_exec_autocmds('BufWinEnter', { buffer = info.buf })
    end,
  },
}, {
  { 'BufWinEnter', 'WinEnter', 'FileChangedShellPost' },
  {
    desc = 'Automatically change local current directory.',
    callback = function(info)
      if info.file == '' or vim.bo[info.buf].bt ~= '' then
        return
      end

      local lsp_root_dir
      local bufname = vim.api.nvim_buf_get_name(info.buf)
      for _, dir in ipairs(vim.g._lsp_root_dirs or {}) do
        if require('utils.fs').contains(dir, bufname) then
          lsp_root_dir = dir
          break
        end
      end

      local root_dir = lsp_root_dir
        or vim.fs.root(info.file, require('utils.fs').root_patterns)
        or vim.fs.dirname(info.file)

      -- Prevent unnecessary directory change, which triggers
      -- DirChanged autocmds that may update winbar unexpectedly
      if not root_dir or root_dir == vim.fn.getcwd(0) then
        return
      end
      for _, win in ipairs(vim.fn.win_findbuf(info.buf)) do
        vim.api.nvim_win_call(win, function()
          pcall(vim.cmd.lcd, {
            root_dir,
            mods = {
              silent = true,
              emsg_silent = true,
            },
          })
        end)
      end
    end,
  },
})

augroup('PromptBufKeymaps', {
  'BufEnter',
  {
    desc = 'Undo automatic <C-w> remap in prompt buffers.',
    callback = function(info)
      if vim.bo[info.buf].buftype == 'prompt' then
        vim.keymap.set('i', '<C-w>', '<C-S-W>', { buffer = info.buf })
      end
    end,
  },
})

augroup('QuickFixAutoOpen', {
  'QuickFixCmdPost',
  {
    desc = 'Open quickfix window if there are results.',
    callback = function(info)
      if #vim.fn.getqflist() > 1 then
        vim.schedule(vim.cmd[info.match:find('^l') and 'lwindow' or 'cwindow'])
      end
    end,
  },
})

augroup('KeepWinRatio', {
  { 'VimResized', 'TabEnter' },
  {
    desc = 'Keep window ratio after resizing nvim.',
    callback = function()
      vim.cmd.wincmd('=')
      require('utils.win').restratio(vim.api.nvim_tabpage_list_wins(0))
    end,
  },
}, {
  { 'TermOpen', 'WinResized', 'WinNew' },
  {
    desc = 'Record window ratio.',
    callback = function()
      -- Don't record ratio if window resizing is caused by vim resizing
      -- (changes in &lines or &columns)
      local lines, columns = vim.go.lines, vim.go.columns
      local _lines, _columns = vim.g._lines, vim.g._columns
      if _lines and lines ~= _lines or _columns and columns ~= _columns then
        vim.g._lines = lines
        vim.g._columns = columns
        return
      end
      require('utils.win').saveratio(vim.v.event.windows)
    end,
  },
})

-- Show cursor line and cursor column only in current window
augroup('AutoHlCursorLine', {
  'WinEnter',
  {
    desc = 'Show cursorline and cursorcolumn in current window.',
    callback = function()
      if vim.w._cul and not vim.wo.cul then
        vim.wo.cul = true
        vim.w._cul = nil
      end
      if vim.w._cuc and not vim.wo.cuc then
        vim.wo.cuc = true
        vim.w._cuc = nil
      end

      local prev_win = vim.fn.win_getid(vim.fn.winnr('#'))
      if prev_win ~= 0 then
        local w = vim.w[prev_win]
        local wo = vim.wo[prev_win]
        w._cul = wo.cul
        w._cuc = wo.cuc
        wo.cul = false
        wo.cuc = false
      end
    end,
  },
})

augroup('FixCmdLineIskeyword', {
  'CmdLineEnter',
  {
    desc = 'Have consistent &iskeyword and &lisp in Ex command-line mode.',
    pattern = '[:>/?=@]',
    callback = function(info)
      -- Don't reset 'iskeyword' and 'lisp' in insert or append command-line
      -- mode ('-'): if we are inserting into a lisp file, we want to have the
      -- same behavior as in insert mode
      vim.g._isk_lisp_buf = info.buf
      vim.g._isk_save = vim.bo[info.buf].isk
      vim.g._lisp_save = vim.bo[info.buf].lisp
      vim.cmd.setlocal('isk&')
      vim.cmd.setlocal('lisp&')
    end,
  },
}, {
  'CmdLineLeave',
  {
    desc = 'Restore &iskeyword after leaving command-line mode.',
    pattern = '[:>/?=@]',
    callback = function()
      if
        vim.g._isk_lisp_buf
        and vim.api.nvim_buf_is_valid(vim.g._isk_lisp_buf)
        and vim.g._isk_save ~= vim.b[vim.g._isk_lisp_buf].isk
      then
        vim.bo[vim.g._isk_lisp_buf].isk = vim.g._isk_save
        vim.bo[vim.g._isk_lisp_buf].lisp = vim.g._lisp_save
        vim.g._isk_save = nil
        vim.g._lisp_save = nil
        vim.g._isk_lisp_buf = nil
      end
    end,
  },
})

augroup('SpecialBufHl', {
  { 'BufWinEnter', 'BufNew', 'FileType', 'TermOpen' },
  {
    desc = 'Set background color for special buffers.',
    callback = function(info)
      if vim.bo[info.buf].bt == '' then
        return
      end
      local stat = vim.uv.fs_stat(vim.api.nvim_buf_get_name(info.buf))
      if stat and stat.type == 'file' then
        return
      end
      -- Current window isn't necessarily the window of the buffer that
      -- triggered the event, use `bufwinid()` to get the first window of
      -- the triggering buffer. We can also use `win_findbuf()` to get all
      -- windows that display the triggering buffer, but it is slower and using
      -- `bufwinid()` is enough for our purpose.
      local winid = vim.fn.bufwinid(info.buf)
      if winid == -1 then
        return
      end
      vim.api.nvim_win_call(winid, function()
        local wintype = vim.fn.win_gettype()
        if wintype == 'popup' or wintype == 'autocmd' then
          return
        end
        vim.opt_local.winhl:append({
          Normal = 'NormalSpecial',
          EndOfBuffer = 'NormalSpecial',
        })
      end)
    end,
  },
}, {
  { 'UIEnter', 'ColorScheme', 'OptionSet' },
  {
    desc = 'Set special buffer normal hl.',
    callback = function(info)
      if info.event == 'OptionSet' and info.match ~= 'background' then
        return
      end
      local hl = require('utils.hl')
      local blended = hl.blend('Normal', 'CursorLine')
      hl.set_default(0, 'NormalSpecial', blended)
    end,
  },
})
