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
    desc = 'Detect big files.',
    callback = function(info)
      vim.g.bigfile_max_size = vim.g.bigfile_max_size or 1048576

      local stat = vim.uv.fs_stat(info.match)
      if stat and stat.size > vim.g.bigfile_max_size then
        vim.b[info.buf].bigfile = true
      end
    end,
  },
}, {
  { 'BufEnter', 'TextChanged' },
  {
    desc = 'Detect big files.',
    callback = function(info)
      vim.g.bigfile_max_lines = vim.g.bigfile_max_lines or 32768

      local buf = info.buf
      if vim.b[buf].bigfile then
        return
      end

      if vim.api.nvim_buf_line_count(buf) > vim.g.bigfile_max_lines then
        vim.b[buf].bigfile = true
      end
    end,
  },
}, {
  'FileType',
  {
    once = true,
    desc = 'Prevent treesitter and LSP from attaching to big files.',
    callback = function(info)
      vim.api.nvim_del_autocmd(info.id)

      local ts_get_parser = vim.treesitter.get_parser
      local ts_foldexpr = vim.treesitter.foldexpr
      local lsp_start = vim.lsp.start

      ---@diagnostic disable-next-line: duplicate-set-field
      function vim.treesitter.get_parser(buf, ...)
        if buf == nil or buf == 0 then
          buf = vim.api.nvim_get_current_buf()
        end
        -- HACK: Getting parser for a big buffer can freeze nvim, so return a
        -- fake parser on an empty buffer if current buffer is big
        if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].bigfile then
          return vim.treesitter._create_parser(
            vim.api.nvim_create_buf(false, true),
            vim.treesitter.language.get_lang(vim.bo.ft) or vim.bo.ft
          )
        end
        return ts_get_parser(buf, ...)
      end

      ---@diagnostic disable-next-line: duplicate-set-field
      function vim.treesitter.foldexpr(...)
        if vim.b.bigfile then
          return
        end
        return ts_foldexpr(...)
      end

      ---@diagnostic disable-next-line: duplicate-set-field
      function vim.lsp.start(...)
        if vim.b.bigfile then
          return
        end
        return lsp_start(...)
      end
    end,
  },
}, {
  'BufReadPre',
  {
    desc = 'Disable options in big files.',
    callback = function(info)
      local buf = info.buf
      if not vim.b[buf].bigfile then
        return
      end
      vim.api.nvim_buf_call(buf, function()
        vim.opt_local.spell = false
        vim.opt_local.swapfile = false
        vim.opt_local.undofile = false
        vim.opt_local.breakindent = false
        vim.opt_local.foldmethod = 'manual'
      end)
    end,
  },
}, {
  { 'BufEnter', 'TextChanged', 'FileType' },
  {
    desc = 'Stop treesitter in big files.',
    callback = function(info)
      local buf = info.buf
      if vim.b[buf].bigfile and require('utils.ts').hl_is_active(buf) then
        vim.treesitter.stop(buf)
        vim.bo[buf].syntax = vim.filetype.match({ buf = buf })
          or vim.bo[buf].bt
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
        end,
      })
    end,
  },
})

augroup('AutoCwd', {
  'BufEnter',
  {
    desc = 'Automatically change local current directory.',
    nested = true,
    callback = function(info)
      ---Set cwd to `root_dir` for all windows for given buffer `buf`
      ---@param buf integer
      ---@param root_dir string
      local function buf_lcd(buf, root_dir)
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end

        if vim.b[buf]._root_dir ~= root_dir then
          vim.b[buf]._root_dir = root_dir
        end

        for _, win in ipairs(vim.fn.win_findbuf(buf)) do
          vim.api.nvim_win_call(win, function()
            -- Prevent unnecessary directory change, which triggers
            -- DirChanged autocmds that may update winbar unexpectedly
            if root_dir == vim.fn.getcwd(0) then
              return
            end
            pcall(vim.cmd.lcd, {
              root_dir,
              mods = {
                silent = true,
                emsg_silent = true,
              },
            })
          end)
        end
      end

      local file = info.file
      local buf = info.buf

      local root_dir_cached = vim.b[buf]._root_dir
      if root_dir_cached and vim.fn.isdirectory(root_dir_cached) == 1 then
        buf_lcd(buf, root_dir_cached)
        return
      end

      -- Don't automatically change cwd in special buffers, e.g. help buffers
      -- or oil preview buffers
      if file == '' or vim.bo[buf].bt ~= '' then
        return
      end

      local fs_utils = require('utils.fs')
      local root_dir = vim.fs.root(file, fs_utils.root_markers)

      if
        not root_dir
        or fs_utils.is_home_dir(root_dir)
        or fs_utils.is_root_dir(root_dir)
      then
        root_dir = vim.fs.dirname(file)
      end

      if not root_dir then
        return
      end

      buf_lcd(buf, root_dir)
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
  { 'BufEnter', 'BufNew', 'FileType', 'TermOpen' },
  {
    desc = 'Set background color for special buffers.',
    callback = function(info)
      if vim.bo[info.buf].bt == '' then
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
      local wintype = vim.fn.win_gettype(winid)
      if wintype == 'popup' or wintype == 'autocmd' then
        return
      end
      vim.api.nvim_win_call(winid, function()
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

augroup('SessionWipeEmptyBufs', {
  'SessionLoadPost',
  {
    desc = 'Wipe empty buffers after loading session.',
    nested = true,
    callback = function()
      ---Check if a buffer is valid, a valid buffer:
      --- - has non-empty contents, or
      --- - has corresponding file on disk, or
      --- - filename contains '://' (special/remote files)
      ---@param buf integer
      ---@return boolean
      local function buf_is_valid(buf)
        if not require('utils.buf').is_empty(buf) then
          return true
        end
        local bufname = vim.api.nvim_buf_get_name(buf)
        if bufname:match('://') or vim.uv.fs_stat(bufname) then
          return true
        end
        return false
      end

      ---Check if a window is normal (has empty win type)
      ---@param win integer
      ---@return boolean
      local function win_is_normal(win)
        return vim.fn.win_gettype(win) == ''
      end

      ---Get list of normal windows in given tabpage
      ---@param tab integer tabpage id
      ---@return integer[]
      local function tabpage_list_normal_wins(tab)
        return vim
          .iter(vim.api.nvim_tabpage_list_wins(tab))
          :filter(win_is_normal)
          :totable()
      end

      local blacklist = {} ---@type table<integer, true>
      local whitelist = {} ---@type table<integer, true>

      -- Clean up windows and add invalid buffers to blacklist
      for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        for _, win in ipairs(tabpage_list_normal_wins(tab)) do
          -- Closing the last normal window will close that tab or break
          -- tabpage layout, skip
          if #tabpage_list_normal_wins(tab) <= 1 then
            break
          end
          if not vim.api.nvim_win_is_valid(win) then
            goto continue
          end

          -- Don't close window if containing buffer is valid
          local buf = vim.api.nvim_win_get_buf(win)
          if buf_is_valid(buf) then
            goto continue
          end
          blacklist[buf] = true

          vim.api.nvim_win_close(win, false)
          ::continue::
        end
      end

      -- Find out invalid buffers that cannot be wiped out due to constraints
      for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        if #tabpage_list_normal_wins(tab) > 1 then
          goto continue
        end
        -- Tabpage has <= 1 normal windows -- cannot wipe any buffer shown
        -- in this tabpage else the tabpage will be closed or the layout will
        -- change
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
          whitelist[vim.api.nvim_win_get_buf(win)] = true
        end
        ::continue::
      end

      -- Wipe out invalid buffers
      for buf, _ in pairs(blacklist) do
        if not whitelist[buf] and vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, {})
        end
      end
    end,
  },
})

augroup('ColorSchemeRestore', {
  { 'UIEnter', 'OptionSet' },
  {
    nested = true, -- invoke Colorscheme event for winbar plugin to clear bg for nvim < 0.11
    callback = function(info)
      if info.event == 'OptionSet' then
        if info.match ~= 'termguicolors' then
          return
        end
        if vim.go.termguicolors then
          pcall(vim.api.nvim_del_autocmd, info.id)
        end
      end

      ---@param colors_name string
      ---@return nil
      local function load_colorscheme(colors_name)
        local colors_path = vim.fs.joinpath(
          vim.fn.stdpath('config') --[[@as string]],
          'colors',
          colors_name .. '.lua'
        )
        if vim.fn.filereadable(colors_path) == 1 then
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

      -- 1. Restore dark/light background and colorscheme from json so that nvim
      --    "remembers" the background and colorscheme when it is restarted.
      -- 2. Spawn setbg/setcolors on colorscheme change to make other nvim instances
      --    and system color consistent with the current nvim instance.

      local json = require('utils.json')
      local colors_file = vim.fs.joinpath(
        vim.fn.stdpath('state') --[[@as string]],
        'colors.json'
      )

      local c = json.read(colors_file)
      c.colors_name = c.colors_name or 'macro'

      if c.bg then
        vim.go.bg = c.bg
      end
      if c.colors_name and c.colors_name ~= vim.g.colors_name then
        load_colorscheme(c.colors_name)
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
              local d = json.read(colors_file)
              if d.colors_name == vim.g.colors_name and d.bg == vim.go.bg then
                return
              end

              if d.colors_name ~= vim.g.colors_name then
                d.colors_name = vim.g.colors_name
                pcall(vim.system, { 'setcolor', vim.g.colors_name })
              end
              if d.bg ~= vim.go.bg and vim.go.termguicolors then
                d.bg = vim.go.bg
                pcall(vim.system, { 'setbg', vim.go.bg })
              end

              json.write(colors_file, d)
            end)
          end,
        },
      })
    end,
  },
})
