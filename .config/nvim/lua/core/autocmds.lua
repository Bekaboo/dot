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

-- This can only handle cases where the big file exists on disk before opening
-- it but not big buffers without corresponding files
-- TODO: Handle big buffers without corresponding files
augroup('BigFile', {
  'BufReadPre',
  {
    desc = 'Disable options in big files.',
    callback = function(info)
      local stat = vim.uv.fs_stat(info.match)
      if not stat or stat.size <= 1048576 then
        return
      end

      vim.api.nvim_buf_call(info.buf, function()
        vim.b.bigfile = true
        vim.opt_local.colorcolumn = ''
        vim.opt_local.foldcolumn = '0'
        vim.opt_local.signcolumn = 'no'
        vim.opt_local.statuscolumn = ''
        vim.opt_local.winbar = ''
        vim.opt_local.spell = false
        vim.opt_local.swapfile = false
        vim.opt_local.undofile = false
        vim.opt_local.breakindent = false
      end)
    end,
  },
}, {
  'BufReadPre',
  {
    once = true,
    desc = 'Disable treesitter and LSP in big files.',
    callback = function()
      local ts_get_parser = vim.treesitter.get_parser
      local lsp_start = vim.lsp.start

      ---@diagnostic disable-next-line: duplicate-set-field
      function vim.treesitter.get_parser(buf, ...)
        if buf == nil or buf == 0 then
          buf = vim.api.nvim_get_current_buf()
        end
        if not vim.api.nvim_buf_is_valid(buf) then
          error(string.format('Getting parser for invalid buffer %d', buf))
        end
        if vim.b[buf].bigfile then
          error(
            string.format(
              'Getting parser for big file %s',
              vim.api.nvim_buf_get_name(buf)
            )
          )
        end
        return ts_get_parser(buf, ...)
      end

      ---@diagnostic disable-next-line: duplicate-set-field
      function vim.lsp.start(...)
        if vim.b.bigfile then
          return
        end
        return lsp_start(...)
      end

      return true
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
      autocmd('FileType', {
        once = true,
        buffer = info.buf,
        callback = function(i)
          local ft = vim.bo[i.buf].ft
          if ft ~= 'gitcommit' and ft ~= 'gitrebase' then
            vim.cmd.normal({
              'g`"zvzz',
              bang = true,
              mods = { emsg_silent = true },
            })
          end
          return true
        end,
      })
    end,
  },
})

augroup('AutoCwd', {
  'LspAttach',
  {
    desc = 'Record LSP root directories in `_G._lsp_root_dirs`.',
    nested = true,
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

      local fs_utils = require('utils.fs')

      -- Keep only shortest root dir in `_G._lsp_root_dirs`,
      -- e.g. if we have `~/project` and `~/project/subdir`, keep only
      -- `~/project`
      _G._lsp_root_dirs = _G._lsp_root_dirs or {}
      for i, dir in ipairs(_G._lsp_root_dirs) do
        if fs_utils.contains(dir, root_dir) then
          return
        end
        if fs_utils.contains(root_dir, dir) then
          table.remove(_G._lsp_root_dirs, i)
        end
      end
      table.insert(_G._lsp_root_dirs, root_dir)
    end,
  },
}, {
  { 'BufWinEnter', 'WinEnter', 'FileChangedShellPost', 'LspAttach' },
  {
    desc = 'Automatically change local current directory.',
    nested = true,
    callback = function(info)
      if info.file == '' or vim.bo[info.buf].bt ~= '' then
        return
      end

      local fs_utils = require('utils.fs')
      local bufname = vim.api.nvim_buf_get_name(info.buf)

      local lsp_root_dir
      for _, dir in ipairs(_G._lsp_root_dirs or {}) do
        if fs_utils.contains(dir, bufname) then
          lsp_root_dir = dir
          break
        end
      end

      local root_dir = lsp_root_dir
        or vim.fs.root(info.file, fs_utils.root_patterns)

      if not root_dir or root_dir == vim.uv.os_homedir() then
        root_dir = vim.fs.dirname(info.file)
      end

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
  { 'ColorScheme', 'OptionSet' },
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

augroup('SessionCloseEmptyWins', {
  'SessionLoadPost',
  {
    desc = 'Close empty windows after loading session.',
    nested = true,
    callback = function()
      for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        local wins = vim.tbl_filter(function(win)
          return vim.fn.win_gettype(win) == ''
        end, vim.api.nvim_tabpage_list_wins(tab))
        if #wins <= 1 then
          goto continue
        end

        for _, win in ipairs(wins) do
          local buf = vim.api.nvim_win_get_buf(win)
          local line_count = vim.api.nvim_buf_line_count(buf)
          if
            line_count == 0
            or line_count == 1
              and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ''
              and not vim.uv.fs_stat(vim.api.nvim_buf_get_name(buf))
          then
            vim.api.nvim_win_close(win, false)
          end
        end
        ::continue::
      end
    end,
  },
})

augroup('ColorSchemeRestore', {
  'UIEnter',
  {
    once = true,
    nested = true, -- invoke Colorscheme event for winbar plugin to clear bg for nvim < 0.11
    callback = function()
      ---@param colors_name string
      ---@return nil
      local function load_colorscheme(colors_name)
        local colors_path = vim.fs.joinpath(
          vim.fn.stdpath('config'), --[[@as string]]
          'colors',
          colors_name .. '.lua'
        )
        if vim.uv.fs_stat(colors_path) then
          dofile(colors_path)
          vim.schedule(function()
            vim.api.nvim_exec_autocmds('ColorScheme', {})
          end)
        else
          vim.cmd.colorscheme({
            args = { colors_name },
            mods = { emsg_silent = true },
          })
        end
      end

      -- Colorschemes other than the default colorscheme looks bad when the terminal
      -- does not support truecolor
      if not vim.go.termguicolors then
        load_colorscheme('default')
        return
      end

      local json = require('utils.json')
      local colors_file = vim.fs.joinpath(
        vim.fn.stdpath('state'), --[[@as string]]
        'colors.json'
      )

      -- 1. Restore dark/light background and colorscheme from json so that nvim
      --    "remembers" the background and colorscheme when it is restarted.
      -- 2. Spawn setbg/setcolors on colorscheme change to make other nvim instances
      --    and system color consistent with the current nvim instance.

      local saved = json.read(colors_file)
      saved.colors_name = saved.colors_name or 'macro'

      if saved.bg then
        vim.go.bg = saved.bg
      end

      if saved.colors_name and saved.colors_name ~= vim.g.colors_name then
        load_colorscheme(saved.colors_name)
      end

      augroup('ColorSchemeSync', {
        'Colorscheme',
        {
          nested = true,
          desc = 'Spawn setbg/setcolors on colorscheme change.',
          callback = function()
            if vim.g.script_set_bg or vim.g.script_set_colors then
              return
            end

            vim.schedule(function()
              local data = json.read(colors_file)
              if
                data.colors_name ~= vim.g.colors_name or data.bg ~= vim.go.bg
              then
                data.colors_name = vim.g.colors_name
                data.bg = vim.go.bg
                if not json.write(colors_file, data) then
                  return
                end
              end

              pcall(vim.system, { 'setbg', vim.go.bg })
              pcall(vim.system, { 'setcolor', vim.g.colors_name })
            end)
          end,
        },
      })

      return true
    end,
  },
})
