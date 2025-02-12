local oil = require('oil')
local icons = require('utils.static').icons
local icon_file = vim.trim(icons.File)
local icon_dir = vim.trim(icons.Folder)

local preview_wins = {} ---@type table<integer, integer>
local preview_bufs = {} ---@type table<integer, integer>
local preview_debounce = 16 -- ms
local preview_request_last_timestamp = 0

---Change window-local directory to `dir`
---@param dir string
---@return nil
local function lcd(dir)
  local ok = pcall(vim.cmd.lcd, {
    dir,
    mods = {
      silent = true,
      emsg_silent = true,
    },
  })
  if not ok then
    vim.notify('[oil.nvim] failed to cd to ' .. dir, vim.log.levels.WARN)
  end
end

---End preview for oil window `win`
---Close preview window and delete preview buffer
---@param oil_win? integer oil window ID
---@return nil
local function preview_finish(oil_win)
  oil_win = oil_win or vim.api.nvim_get_current_win()
  local preview_win = preview_wins[oil_win]
  local preview_buf = preview_bufs[oil_win]
  if
    preview_win
    and vim.api.nvim_win_is_valid(preview_win)
    and vim.fn.winbufnr(preview_win) == preview_buf
  then
    vim.api.nvim_win_close(preview_win, true)
  end
  if preview_buf and vim.api.nvim_win_is_valid(preview_buf) then
    vim.api.nvim_win_close(preview_buf, true)
  end
  preview_wins[oil_win] = nil
  preview_bufs[oil_win] = nil
end

---@return string
local function preview_get_filler()
  return vim.opt_local.fillchars:get().diff or '-'
end

---Generate lines to show a message when preview is not available
---@param msg string
---@param height integer
---@param width integer
---@return string[]
local function preview_msg(msg, height, width)
  local lines = {}
  local fillchar = preview_get_filler()
  local msglen = #msg + 4
  local padlen_l = math.max(0, math.floor((width - msglen) / 2))
  local padlen_r = math.max(0, width - msglen - padlen_l)
  local line_fill = fillchar:rep(width)
  local half_fill_l = fillchar:rep(padlen_l)
  local half_fill_r = fillchar:rep(padlen_r)
  local line_above = half_fill_l .. string.rep(' ', msglen) .. half_fill_r
  local line_below = line_above
  local line_msg = half_fill_l .. '  ' .. msg .. '  ' .. half_fill_r
  local half_height_u = math.max(0, math.floor((height - 3) / 2))
  local half_height_d = math.max(0, height - 3 - half_height_u)
  for _ = 1, half_height_u do
    table.insert(lines, line_fill)
  end
  table.insert(lines, line_above)
  table.insert(lines, line_msg)
  table.insert(lines, line_below)
  for _ = 1, half_height_d do
    table.insert(lines, line_fill)
  end
  return lines
end

---@param win integer
---@param all boolean? load all lines from file, default false
local function preview_set_lines(win, all)
  local buf = vim.api.nvim_win_get_buf(win)
  local bufname = vim.fn.bufname(buf)

  local path = bufname:match('oil_preview://(.*)')
  if not path then
    return
  end

  if vim.b[buf]._oil_preview_updated == bufname then
    return
  end

  vim.b[buf]._oil_preview_updated = nil
  if all then
    vim.b[buf]._oil_preview_updated = bufname
  end

  local stat = vim.uv.fs_stat(path)
  local win_height = vim.api.nvim_win_get_height(win)
  local win_width = vim.api.nvim_win_get_width(win)
  local num_lines = all and vim.g.bigfile_max_lines
    or math.min(win_height, vim.g.bigfile_max_lines or math.huge)

  local lines = (function()
    if not stat then
      vim.b[buf]._oil_preview_msg_shown = bufname
      return preview_msg('Invalid path', win_height, win_width)
    end

    if stat.type == 'directory' then
      return vim
        .iter(vim.gsplit(vim.system({ 'ls', '-lhA', path }):wait().stdout, '\n'))
        :take(num_lines)
        :map(function(line)
          local result = vim.fn.match(line, '\\v^[-dpls][-rwxs]{9}') == -1
              and line
            or line:sub(1, 1) .. ' ' .. line:sub(2)
          return result
        end)
        :totable()
    end

    if stat.size == 0 then
      vim.b[buf]._oil_preview_msg_shown = bufname
      return preview_msg('Empty file', win_height, win_width)
    end

    if not vim.system({ 'file', path }):wait().stdout:match('text') then
      vim.b[buf]._oil_preview_msg_shown = bufname
      return preview_msg('Binary file', win_height, win_width)
    end

    vim.b[buf]._oil_preview_syntax = bufname
    return vim
      .iter(io.lines(path))
      :take(num_lines)
      :map(function(line)
        return (line:gsub('\x0d$', ''))
      end)
      :totable()
  end)()

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

---Disable window options, e.g. spell, number, signcolumn, etc. in given window
---@param win integer? default to current window
local function preview_disable_win_opts(win)
  vim.api.nvim_win_call(win or 0, function()
    vim.opt_local.spell = false
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
    vim.opt_local.signcolumn = 'no'
    vim.opt_local.foldcolumn = '0'
    vim.opt_local.statuscolumn = ''
    vim.opt_local.winbar = ''
  end)
end

---Set window options, e.g. spell, number, signcolumn, etc. to global value
---@param win integer? default to current window
local function preview_restore_win_opts(win)
  vim.api.nvim_win_call(win or 0, function()
    vim.opt_local.spell = vim.go.spell
    vim.opt_local.number = vim.go.number
    vim.opt_local.relativenumber = vim.go.relativenumber
    vim.opt_local.signcolumn = vim.go.signcolumn
    vim.opt_local.foldcolumn = vim.go.foldcolumn
    vim.opt_local.statuscolumn = vim.go.statuscolumn
    vim.opt_local.winbar = vim.go.winbar
  end)
end

---Preview file under cursor in a split
---@return nil
local function preview()
  local entry = oil.get_cursor_entry()
  local fname = entry and entry.name
  local dir = oil.get_current_dir()
  if not dir or not fname then
    return
  end

  local oil_win = vim.api.nvim_get_current_win()
  local preview_win = preview_wins[oil_win]
  local preview_buf = preview_bufs[oil_win]
  if
    not preview_win
    or not preview_buf
    or not vim.api.nvim_win_is_valid(preview_win)
    or not vim.api.nvim_buf_is_valid(preview_buf)
  then
    local oil_win_height = vim.api.nvim_win_get_height(oil_win)
    local oil_win_width = vim.api.nvim_win_get_width(oil_win)
    vim.cmd.new({
      mods = {
        vertical = oil_win_width > 3 * oil_win_height,
      },
    })
    preview_win = vim.api.nvim_get_current_win()
    preview_buf = vim.api.nvim_get_current_buf()
    preview_wins[oil_win] = preview_win
    preview_bufs[oil_win] = preview_buf
    vim.bo[preview_buf].swapfile = false
    vim.bo[preview_buf].buflisted = false
    vim.bo[preview_buf].buftype = 'nofile'
    vim.bo[preview_buf].bufhidden = 'wipe'
    vim.bo[preview_buf].filetype = 'oil_preview'
    vim.api.nvim_set_current_win(oil_win)
  end

  -- Follow symlinks
  local fpath = vim.F.npcall(vim.uv.fs_realpath, vim.fs.joinpath(dir, fname))
    or ''

  -- Preview buffer already contains contents of file to preview
  local preview_bufname = vim.fn.bufname(preview_buf)
  local preview_bufnewname = 'oil_preview://' .. fpath
  if preview_bufname == preview_bufnewname then
    return
  end
  vim.api.nvim_buf_set_name(preview_buf, preview_bufnewname)

  ---Edit corresponding file in oil preview buffer
  ---@return nil
  local function preview_edit()
    local view = vim.fn.winsaveview()
    vim.cmd.edit(fpath)
    preview_finish(oil_win)
    pcall(vim.fn.winrestview, view)
  end

  -- Set keymap for opening the file from preview buffer
  vim.keymap.set('n', '<CR>', preview_edit, { buffer = preview_buf })
  vim.api.nvim_create_autocmd('BufReadCmd', {
    desc = 'Edit corresponding file in oil preview buffers.',
    group = vim.api.nvim_create_augroup('OilPreviewEdit', {}),
    buffer = preview_buf,
    callback = vim.schedule_wrap(preview_edit),
  })

  -- If previewing a directory, change cwd to that directory
  -- so that we can `gf` to files in the preview buffer;
  -- else change cwd to the parent directory of the file in preview
  local stat = vim.uv.fs_stat(fpath)
  vim.api.nvim_win_call(preview_win, function()
    local target_dir = (stat or {}).type == 'directory' and fpath or dir
    if vim.fn.getcwd(0) ~= target_dir then
      lcd(target_dir)
    end
    -- Move cursor to the first line of the preview buffer, so that we always
    -- see the beginning of the file when we start previewing a new file
    vim.cmd('0')
  end)

  vim.api.nvim_buf_call(preview_buf, function()
    vim.treesitter.stop(preview_buf)
    vim.bo.syntax = ''
    -- Because we are reusing the same preview buffer for different files, we
    -- need to clear the `bigfile` flag so that we can enable treesitter
    -- when previewing smaller files after previewing big files.
    vim.b.bigfile = nil
  end)

  preview_set_lines(preview_win)
  preview_restore_win_opts(preview_win)

  -- Colorize preview buffer with syntax highlighting
  if (stat or {}).type == 'directory' then
    -- Disable window decorations when previewing a directory to match oil
    -- window appearance
    preview_disable_win_opts(preview_win)
    vim.api.nvim_buf_call(preview_buf, function()
      vim.cmd([[
        syn match OilDirPreviewHeader /^total.*/
        syn match OilDirPreviewTypeFile /^-/ nextgroup=OilDirPreviewFilePerms skipwhite
        syn match OilDirPreviewTypeDir /^d/ nextgroup=OilDirPreviewDirPerms skipwhite
        syn match OilDirPreviewTypeFifo /^p/ nextgroup=OilDirPreviewFifoPerms skipwhite
        syn match OilDirPreviewTypeLink /^l/ nextgroup=OilDirPreviewLinkPerms skipwhite
        syn match OilDirPreviewTypeSocket /^s/ nextgroup=OilDirPreviewSocketPerms skipwhite

        for type in ['File', 'Dir', 'Fifo', 'Link', 'Socket']
          exe substitute('syn match OilDirPreview%sPerms /\v[-rwxs]{9}/ contained
                        \ contains=OilDirPreviewPermRead,OilDirPreviewPermWrite,
                                 \ OilDirPreviewPermExec,OilDirPreviewPermSetuid,OilDirPreviewPermNone
                        \ nextgroup=OilDirPreview%sNumHardLinksNormal,
                                  \ OilDirPreview%sNumHardLinksMulti
                        \ skipwhite', '%s', type, 'g')
          exe substitute('syn match OilDirPreview%sNumHardLinksNormal /1/ contained nextgroup=OilDirPreview%sUser skipwhite', '%s', type, 'g')
          exe substitute('syn match OilDirPreview%sNumHardLinksMulti /\v[2-9]\d*|1\d+/ contained nextgroup=OilDirPreview%sUser skipwhite', '%s', type, 'g')
          exe substitute('syn match OilDirPreview%sUser /\v\S+/ contained nextgroup=OilDirPreview%sGroup skipwhite', '%s', type, 'g')
          exe substitute('syn match OilDirPreview%sGroup /\v\S+/ contained nextgroup=OilDirPreview%sSize skipwhite', '%s', type, 'g')
          exe substitute('syn match OilDirPreview%sSize /\v\S+/ contained nextgroup=OilDirPreview%sTime skipwhite', '%s', type, 'g')
          exe substitute('syn match OilDirPreview%sTime /\v(\S+\s+){3}/ contained
                        \ nextgroup=OilDirPreview%s,OilDirPreview%sHidden
                        \ skipwhite', '%s', type, 'g')

          exe substitute('hi def link OilDirPreview%sNumHardLinksNormal Number', '%s', type, 'g')
          exe substitute('hi def link OilDirPreview%sNumHardLinksMulti OilDirPreview%sNumHardLinksNormal', '%s', type, 'g')
          exe substitute('hi def link OilDirPreview%sSize Number', '%s', type, 'g')
          exe substitute('hi def link OilDirPreview%sTime String', '%s', type, 'g')
          exe substitute('hi def link OilDirPreview%sUser Operator', '%s', type, 'g')
          exe substitute('hi def link OilDirPreview%sGroup Structure', '%s', type, 'g')
       endfor

        syn match OilDirPreviewPermRead /r/ contained
        syn match OilDirPreviewPermWrite /w/ contained
        syn match OilDirPreviewPermExec /x/ contained
        syn match OilDirPreviewPermSetuid /s/ contained
        syn match OilDirPreviewPermNone /-/ contained

        syn match OilDirPreviewDir /[^.].*/ contained
        syn match OilDirPreviewFile /[^.].*/ contained
        syn match OilDirPreviewSocket /[^.].*/ contained
        syn match OilDirPreviewLink /[^.].*/ contained contains=OilDirPreviewLinkTarget
        syn match OilDirPreviewLinkTarget /->.*/ contained

        syn match OilDirPreviewDirHidden /\..*/ contained
        syn match OilDirPreviewFileHidden /\..*/ contained
        syn match OilDirPreviewSocketHidden /\..*/ contained
        syn match OilDirPreviewLinkHidden /\..*/ contained contains=OilDirPreviewLinkTargetHidden
        syn match OilDirPreviewLinkTargetHidden /->.*/ contained

        hi def link OilDirPreviewHeader Title
        hi def link OilDirPreviewTypeFile OilTypeFile
        hi def link OilDirPreviewTypeDir OilTypeDir
        hi def link OilDirPreviewTypeFifo OilTypeFifo
        hi def link OilDirPreviewTypeLink OilTypeLink
        hi def link OilDirPreviewTypeSocket OilTypeSocket

        hi def link OilDirPreviewPermRead OilPermissionRead
        hi def link OilDirPreviewPermWrite OilPermissionWrite
        hi def link OilDirPreviewPermExec OilPermissionExecute
        hi def link OilDirPreviewPermSetuid OilPermissionSetuid
        hi def link OilDirPreviewPermNone OilPermissionNone

        hi def link OilDirPreviewDir OilDir
        hi def link OilDirPreviewFile OilFile
        hi def link OilDirPreviewLink OilLink
        hi def link OilDirPreviewLinkTarget OilLinkTarget
        hi def link OilDirPreviewSocket OilSocket

        hi def link OilDirPreviewDirHidden OilDirHidden
        hi def link OilDirPreviewFileHidden OilFileHidden
        hi def link OilDirPreviewLinkHidden OilLinkHidden
        hi def link OilDirPreviewLinkTargetHidden OilLinkTargetHidden
        hi def link OilDirPreviewSocketHidden OilSocketHidden
      ]])
    end)
  elseif vim.b[preview_buf]._oil_preview_syntax == preview_bufnewname then
    local ft = vim.filetype.match({
      buf = preview_buf,
      filename = fpath,
    })
    if
      ft
      -- If file size is larger than the max size for treesitter, don't
      -- start it in preview buffer to prevent highlight change after
      -- actually loading the file
      and (
        stat
          and stat.size
          and vim.g.bigfile_max_size
          and stat.size > vim.g.bigfile_max_size
        or not pcall(vim.treesitter.start, preview_buf, ft)
      )
    then
      vim.bo[preview_buf].syntax = ft
    end
  elseif vim.b[preview_buf]._oil_preview_msg_shown == preview_bufnewname then
    -- Set some window options if showing messages instead of preview
    preview_disable_win_opts(preview_win)
    vim.api.nvim_win_call(preview_win, function()
      vim.cmd.syntax(
        string.format(
          'match NonText /\\V%s/',
          vim.fn.escape(preview_get_filler(), '/?')
        )
      )
    end)
  end
end

local groupid_preview = vim.api.nvim_create_augroup('OilPreview', {})
vim.api.nvim_create_autocmd({ 'CursorMoved', 'WinScrolled' }, {
  desc = 'Update floating preview window when cursor moves or window scrolls.',
  group = groupid_preview,
  pattern = 'oil://*',
  callback = function()
    local oil_win = vim.api.nvim_get_current_win()
    local preview_win = preview_wins[oil_win]
    if not preview_win or not vim.api.nvim_win_is_valid(preview_win) then
      preview_finish()
      return
    end
    local current_request_timestamp = vim.uv.now()
    preview_request_last_timestamp = current_request_timestamp
    vim.defer_fn(function()
      if preview_request_last_timestamp == current_request_timestamp then
        preview()
      end
    end, preview_debounce)
  end,
})

vim.api.nvim_create_autocmd('BufEnter', {
  desc = 'Close preview window when leaving oil buffers.',
  group = groupid_preview,
  callback = function(info)
    if vim.bo[info.buf].filetype ~= 'oil' then
      preview_finish()
    end
  end,
})

vim.api.nvim_create_autocmd('WinClosed', {
  desc = 'Close preview window when closing oil windows.',
  group = groupid_preview,
  callback = function(info)
    local win = tonumber(info.match)
    if win and preview_wins[win] then
      preview_finish(win)
    end
  end,
})

vim.api.nvim_create_autocmd({ 'WinResized', 'WinScrolled' }, {
  desc = 'Update invisible lines in preview buffer.',
  group = groupid_preview,
  callback = function(info)
    local wins = vim.tbl_map(
      function(win)
        return tonumber(win)
      end,
      vim.list_extend(
        { info.match },
        vim.v.event.windows or vim.tbl_keys(vim.v.event)
      )
    )

    for _, win in ipairs(wins) do
      preview_set_lines(win, info.event == 'WinScrolled')
    end
  end,
})

vim.api.nvim_create_autocmd('BufEnter', {
  desc = 'Update invisible lines in preview buffer.',
  group = groupid_preview,
  pattern = '*/oil_preview://*',
  callback = function(info)
    preview_set_lines(vim.fn.bufwinid(info.buf), true)
  end,
})

---Toggle preview window
---@return nil
local function toggle_preview()
  local win = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(win)
  local oil_win = vim.api.nvim_get_current_win()
  local preview_win = preview_wins[oil_win]
  if not preview_win or not vim.api.nvim_win_is_valid(preview_win) then
    preview()
  else
    preview_finish()
  end
  pcall(vim.api.nvim_set_current_win, win)
  pcall(vim.api.nvim_win_set_cursor, win, cursor)
end

local preview_mapping = {
  mode = { 'n', 'x' },
  desc = 'Toggle preview',
  callback = toggle_preview,
}

local permission_hlgroups = setmetatable({
  ['-'] = 'OilPermissionNone',
  ['r'] = 'OilPermissionRead',
  ['w'] = 'OilPermissionWrite',
  ['x'] = 'OilPermissionExecute',
  ['s'] = 'OilPermissionSetuid',
}, {
  __index = function()
    return 'OilDir'
  end,
})

local type_hlgroups = setmetatable({
  ['-'] = 'OilTypeFile',
  ['d'] = 'OilTypeDir',
  ['p'] = 'OilTypeFifo',
  ['l'] = 'OilTypeLink',
  ['s'] = 'OilTypeSocket',
}, {
  __index = function()
    return 'OilTypeFile'
  end,
})

oil.setup({
  columns = {
    {
      'type',
      icons = {
        directory = 'd',
        fifo = 'p',
        file = '-',
        link = 'l',
        socket = 's',
      },
      highlight = function(type_str)
        return type_hlgroups[type_str]
      end,
    },
    {
      'permissions',
      highlight = function(permission_str)
        local hls = {}
        for i = 1, #permission_str do
          local char = permission_str:sub(i, i)
          table.insert(hls, { permission_hlgroups[char], i - 1, i })
        end
        return hls
      end,
    },
    { 'size', highlight = 'Number' },
    { 'mtime', highlight = 'String' },
    {
      'icon',
      default_file = icon_file,
      directory = icon_dir,
      add_padding = false,
    },
  },
  buf_options = {
    buflisted = false,
    bufhidden = 'hide',
  },
  win_options = {
    spell = false,
    number = false,
    relativenumber = false,
    signcolumn = 'no',
    foldcolumn = '0',
    winbar = '',
  },
  cleanup_delay_ms = false,
  delete_to_trash = true,
  skip_confirm_for_simple_edits = true,
  prompt_save_on_select_new_entry = true,
  use_default_keymaps = false,
  view_options = {
    is_always_hidden = function(name)
      return name == '..'
    end,
  },
  keymaps = {
    ['g?'] = 'actions.show_help',
    ['K'] = preview_mapping,
    ['<C-k>'] = preview_mapping,
    ['-'] = 'actions.parent',
    ['='] = 'actions.select',
    ['+'] = 'actions.select',
    ['<CR>'] = 'actions.select',
    ['<C-h>'] = 'actions.toggle_hidden',
    ['gh'] = 'actions.toggle_hidden',
    ['gs'] = 'actions.change_sort',
    ['gx'] = 'actions.open_external',
    ['gY'] = 'actions.copy_entry_filename',
    ['go'] = {
      mode = 'n',
      buffer = true,
      desc = 'Choose an external program to open the entry under the cursor',
      callback = function()
        local entry = oil.get_cursor_entry()
        local dir = oil.get_current_dir()
        if not entry or not dir then
          return
        end
        local entry_path = vim.fs.joinpath(dir, entry.name)
        local response
        vim.ui.input({
          prompt = 'Open with: ',
          completion = 'shellcmd',
        }, function(r)
          response = r
        end)
        if not response then
          return
        end
        print('\n')
        vim.system({ response, entry_path })
      end,
    },
    ['gy'] = {
      mode = 'n',
      buffer = true,
      desc = 'Yank the filepath of the entry under the cursor to a register',
      callback = function()
        local entry = oil.get_cursor_entry()
        local dir = oil.get_current_dir()
        if not entry or not dir then
          return
        end
        local entry_path = vim.fs.joinpath(dir, entry.name)
        vim.fn.setreg('"', entry_path)
        vim.fn.setreg(vim.v.register, entry_path)
        vim.notify(
          string.format(
            "[oil] yanked '%s' to register '%s'",
            entry_path,
            vim.v.register
          )
        )
      end,
    },
  },
  keymaps_help = {
    border = 'solid',
  },
  float = {
    border = 'solid',
    win_options = {
      winblend = 0,
    },
  },
  preview = {
    border = 'solid',
    win_options = {
      winblend = 0,
    },
  },
  progress = {
    border = 'solid',
    win_options = {
      winblend = 0,
    },
  },
})

local groupid = vim.api.nvim_create_augroup('OilSetup', {})
vim.api.nvim_create_autocmd('BufEnter', {
  desc = 'Ensure that oil buffers are not listed.',
  group = groupid,
  pattern = 'oil://*',
  callback = function(info)
    vim.bo[info.buf].buflisted = false
  end,
})

---Change cwd in oil buffer to follow the directory shown in the buffer
---@param buf integer? default to current buffer
local function oil_cd(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].ft ~= 'oil' then
    return
  end

  vim.api.nvim_buf_call(buf, function()
    local oildir = vim.fs.normalize(oil.get_current_dir())
    if vim.fn.isdirectory(oildir) == 0 then
      return
    end

    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      vim.api.nvim_win_call(win, function()
        -- Always change local cwd without checking if current cwd is already
        -- `oildir`, else setting local cwd for preview window can change
        -- (global) cwd of oil buffer unexpectedly
        lcd(oildir)
      end)
    end
  end)
end

for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  oil_cd(buf)
end

vim.api.nvim_create_autocmd({ 'BufEnter', 'TextChanged' }, {
  desc = 'Set cwd to follow directory shown in oil buffers.',
  group = groupid,
  pattern = 'oil://*',
  callback = function(info)
    oil_cd(info.buf)
  end,
})

vim.api.nvim_create_autocmd('BufEnter', {
  desc = 'Record alternate file in dir buffers.',
  group = groupid,
  callback = function(info)
    local buf = info.buf
    local bufname = vim.api.nvim_buf_get_name(buf)
    if vim.fn.isdirectory(bufname) == 1 then
      vim.b[buf]._alt_file = vim.fn.bufnr('#')
    end
  end,
})

vim.api.nvim_create_autocmd('BufEnter', {
  desc = 'Set last cursor position in oil buffers when editing parent dir.',
  group = groupid,
  pattern = 'oil://*',
  callback = function(info)
    -- Only set cursor position when first entering an oil buffer in current window
    -- This prevents cursor from resetting to the original file when switching
    -- between oil and preview windows, e.g.
    -- 1. Open `foo/bar.txt`
    -- 2. Run `:e %:p:h` to open `foo/` in oil - cursor starts on `bar.txt`
    -- 3. Open preview window
    -- 4. Move cursor to different files in oil buffer
    -- 5. Switch to preview window
    -- 6. Switch back to oil buffer
    -- Without this check, cursor would incorrectly reset to `bar.txt`
    -- Setting a boolean flag i.e. set `_oil_entered` to `true` or `false`
    -- is not enough because oil reuses buffers for the same directory, consider
    -- the following case:
    -- 1. `:vsplit`
    -- 2. `:e .` to open oil in one split
    -- 3. `:close`
    -- 4. `:e .` to open oil in another split (reuse oil buffer!)
    -- If we use a boolean flag for `_oil_entered`, we will not able to set cursor
    -- position in oil buffer on step 4 because the flag is set in step 2.
    local win = vim.api.nvim_get_current_win()
    if vim.b[info.buf]._oil_entered == win then
      return
    end
    vim.b[info.buf]._oil_entered = win
    -- Place cursor on the alternate buffer if we are opening
    -- the parent directory of the alternate buffer
    local alt_file = vim.fn.bufnr('#')
    if not vim.api.nvim_buf_is_valid(alt_file) then
      return
    end
    -- Because we use `:e <dir>` to open oil, the alternate file will be a dir
    -- buffer. Retrieve the "real" alternate buffer (file buffer) we recorded
    -- in the dir buffer
    local _alt_file = vim.b[alt_file]._alt_file
    if _alt_file and vim.api.nvim_buf_is_valid(_alt_file) then
      alt_file = _alt_file
    end
    local bufname_alt = vim.api.nvim_buf_get_name(alt_file)
    local parent_url, basename = oil.get_buffer_parent_url(bufname_alt, true)
    if basename then
      local config = require('oil.config')
      local view = require('oil.view')
      if
        not config.view_options.show_hidden
        and config.view_options.is_hidden_file(
          basename,
          (function()
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
              if vim.api.nvim_buf_get_name(buf) == basename then
                return buf
              end
            end
          end)()
        )
      then
        view.toggle_hidden()
      end
      view.set_last_cursor(parent_url, basename)
      view.maybe_set_cursor()
    end
  end,
})

---Set some default hlgroups for oil
---@return nil
local function oil_sethl()
  local sethl = require('utils.hl').set
  sethl(0, 'OilDir', { fg = 'Directory' })
  sethl(0, 'OilDirIcon', { fg = 'Directory' })
  sethl(0, 'OilLink', { fg = 'Constant' })
  sethl(0, 'OilLinkTarget', { fg = 'Special' })
  sethl(0, 'OilCopy', { fg = 'DiagnosticSignHint', bold = true })
  sethl(0, 'OilMove', { fg = 'DiagnosticSignWarn', bold = true })
  sethl(0, 'OilChange', { fg = 'DiagnosticSignWarn', bold = true })
  sethl(0, 'OilCreate', { fg = 'DiagnosticSignInfo', bold = true })
  sethl(0, 'OilDelete', { fg = 'DiagnosticSignError', bold = true })
  sethl(0, 'OilPermissionNone', { fg = 'NonText' })
  sethl(0, 'OilPermissionRead', { fg = 'DiagnosticSignWarn' })
  sethl(0, 'OilPermissionWrite', { fg = 'DiagnosticSignError' })
  sethl(0, 'OilPermissionExecute', { fg = 'DiagnosticSignInfo' })
  sethl(0, 'OilPermissionSetuid', { fg = 'DiagnosticSignHint' })
  sethl(0, 'OilTypeDir', { fg = 'Directory' })
  sethl(0, 'OilTypeFifo', { fg = 'Special' })
  sethl(0, 'OilTypeFile', { fg = 'NonText' })
  sethl(0, 'OilTypeLink', { fg = 'Constant' })
  sethl(0, 'OilTypeSocket', { fg = 'OilSocket' })
end
oil_sethl()

vim.api.nvim_create_autocmd('ColorScheme', {
  desc = 'Set some default hlgroups for oil.',
  group = vim.api.nvim_create_augroup('OilSetDefaultHlgroups', {}),
  callback = oil_sethl,
})
