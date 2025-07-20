local oil = require('oil')
local oil_config = require('oil.config')
local oil_view = require('oil.view')
local icons = require('utils.static').icons
local icon_file = vim.trim(icons.File)
local icon_dir = vim.trim(icons.Folder)

local preview_wins = {} ---@type table<integer, integer>
local preview_bufs = {} ---@type table<integer, integer>
local preview_debounce = 0 -- ms
local preview_decorate_debounce = 16 -- ms
local preview_request_last_timestamp = 0
local preview_decorate_last_timestamp = 0

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

---@param buf integer
---@return string?
local function preview_buf_get_path(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  return vim.fn.bufname(buf):match('oil_preview_%d+://(.*)')
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

---Colorize preview buffer with syntax highlighting, set win opts, etc.
---@param win integer?
---@param hl boolean? whether to set syntax highlighting in preivew buffer, default `true`
local function preview_decorate(win, hl)
  win = win or 0
  hl = hl ~= false

  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  local buf = vim.fn.winbufnr(win)
  local bufname = vim.fn.bufname(buf)
  local path = preview_buf_get_path(buf)
  if not path then
    return
  end

  -- Add syntax highlighting for message fillers
  if vim.b[buf]._oil_preview_msg_shown == bufname then
    -- Set some window options if showing messages instead of preview
    preview_disable_win_opts(win)
    if hl then
      vim.api.nvim_buf_call(buf, function()
        vim.treesitter.stop(buf)
        vim.bo.syntax = ''
        vim.cmd.syntax(
          string.format(
            'match NonText /\\V%s/',
            vim.fn.escape(preview_get_filler(), '/?')
          )
        )
      end)
    end
    return
  end

  -- Add syntax highlighting to directories or files
  vim.uv.fs_stat(
    path,
    vim.schedule_wrap(function(_, stat)
      if not stat or preview_buf_get_path(buf) ~= path then
        return
      end

      -- Add syntax highlighting for `ls` output
      if stat.type == 'directory' then
        -- Disable window decorations when previewing a directory to match oil
        -- window appearance
        preview_disable_win_opts(win)
        if hl then
          vim.api.nvim_buf_call(buf, function()
            vim.treesitter.stop(buf)
            vim.bo.syntax = ''
            vim.cmd([[
              syn match OilDirPreviewHeader /^total.*/
              syn match OilDirPreviewTypeFile /^-/ nextgroup=OilDirPreviewFilePerms skipwhite
              syn match OilDirPreviewTypeDir /^d/ nextgroup=OilDirPreviewDirPerms skipwhite
              syn match OilDirPreviewTypeFifo /^p/ nextgroup=OilDirPreviewFifoPerms skipwhite
              syn match OilDirPreviewTypeLink /^l/ nextgroup=OilDirPreviewLinkPerms skipwhite
              syn match OilDirPreviewTypeSocket /^s/ nextgroup=OilDirPreviewSocketPerms skipwhite

              for type in ['File', 'Dir', 'Fifo', 'Link', 'Socket']
                exe substitute('syn match OilDirPreview%sPerms /\v[-rwxs]{9}[\.\@\+]?/ contained
                              \ contains=OilDirPreviewPermRead,OilDirPreviewPermWrite,
                                       \ OilDirPreviewPermExec,OilDirPreviewPermSetuid,
                                       \ OilDirPreviewPermNone,OilDirPreviewSecurityContext,
                                       \ OilDirPreviewSecurityExtended
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
              syn match OilDirPreviewSecurityContext /\./ contained
              syn match OilDirPreviewSecurityExtended /@\|+/ contained

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
              hi def link OilDirPreviewSecurityContext OilSecurityContext
              hi def link OilDirPreviewSecurityExtended OilSecurityExtended

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
        end
        return
      end

      -- Add syntax/treesitter highlighting for normal files
      if vim.b[buf]._oil_preview_syntax_bufname == bufname then
        preview_restore_win_opts(win)
        if not hl then
          return
        end

        local ft = vim.api.nvim_buf_call(buf, function()
          return vim.filetype.match({
            buf = buf,
            filename = path,
          })
        end)
        if not ft then
          vim.treesitter.stop(buf)
          vim.bo[buf].syntax = ''
          return
        end

        if not pcall(vim.treesitter.start, buf, ft) then
          vim.treesitter.stop(buf)
          vim.bo[buf].syntax = ft
        end
      end
    end)
  )
end

---@param win integer
---@param lines string[]
---@param path string
local function preview_win_set_lines(win, lines, path)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  local buf = vim.fn.winbufnr(win)
  if preview_buf_get_path(buf) ~= path then
    return
  end

  -- Disable syntax when scrolling through files to improve speed
  vim.treesitter.stop(buf)
  vim.bo[buf].syntax = ''

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  preview_decorate(win, false)

  preview_decorate_last_timestamp = preview_decorate_last_timestamp + 1
  local current_decorate_timestamp = preview_decorate_last_timestamp
  vim.defer_fn(function()
    if preview_decorate_last_timestamp == current_decorate_timestamp then
      preview_decorate(win)
    end
  end, preview_decorate_debounce)
end

---@param win integer
---@param all boolean? load all lines from file, default false
local function preview_set_lines(win, all)
  local buf = vim.api.nvim_win_get_buf(win)
  local bufname = vim.fn.bufname(buf)

  local path = preview_buf_get_path(buf)
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

  if not stat then
    vim.b[buf]._oil_preview_msg_shown = bufname
    preview_win_set_lines(
      win,
      preview_msg('Invalid path', win_height, win_width),
      path
    )
    return
  end

  -- Preview directories
  if stat.type == 'directory' then
    if vim.fn.executable('ls') == 0 then
      preview_win_set_lines(
        win,
        preview_msg(
          '`ls` is required to previous directories',
          win_height,
          win_width
        ),
        path
      )
      return
    end

    vim.system(
      {
        'ls',
        oil_config.view_options.show_hidden and '-lhA' or '-lh',
        path,
      },
      { text = true },
      vim.schedule_wrap(function(obj)
        preview_win_set_lines(
          win,
          vim
            .iter(vim.gsplit(obj.stdout, '\n'))
            :take(num_lines)
            :map(function(line)
              local result = vim.fn.match(line, '\\v^[-dpls][-rwxs]{9}') == -1
                  and line
                or line:sub(1, 1) .. ' ' .. line:sub(2)
              return result
            end)
            :totable(),
          path
        )
      end)
    )
    return
  end

  -- Preview files
  local function preview_file()
    if vim.fn.winbufnr(win) ~= buf then
      return
    end

    vim.b[buf]._oil_preview_syntax_bufname = bufname
    preview_win_set_lines(
      win,
      vim
        .iter(io.lines(path))
        :take(num_lines)
        :map(function(line)
          return (line:gsub('\x0d$', ''))
        end)
        :totable(),
      path
    )
  end

  if vim.fn.executable('file') == 0 then
    preview_file()
    return
  end

  -- Use `file` to check and preview text files only
  vim.system(
    { 'file', path },
    { text = true },
    vim.schedule_wrap(function(obj)
      if vim.fn.winbufnr(win) ~= buf then
        return
      end

      if obj.stdout:match('text') or obj.stdout:match('empty') then
        preview_file()
        return
      end

      vim.b[buf]._oil_preview_msg_shown = bufname
      preview_win_set_lines(
        win,
        preview_msg('Binary file', win_height, win_width),
        path
      )
    end)
  )
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
  local path = vim.F.npcall(vim.uv.fs_realpath, vim.fs.joinpath(dir, fname))
    or ''

  -- Preview buffer already contains contents of file to preview
  local preview_bufname = vim.fn.bufname(preview_buf)
  local preview_bufnewname = ('oil_preview_%d://%s'):format(preview_buf, path)
  if preview_bufname == preview_bufnewname then
    return
  end
  vim.api.nvim_buf_set_name(preview_buf, preview_bufnewname)

  ---Edit corresponding file in oil preview buffer
  ---@return nil
  local function preview_edit()
    local view = vim.fn.winsaveview()
    vim.cmd.edit(path)
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
  vim.api.nvim_win_call(preview_win, function()
    local target_dir = vim.fn.isdirectory(path) == 1 and path or dir
    if vim.fn.getcwd(0) ~= target_dir then
      lcd(target_dir)
    end
    -- Move cursor to the first line of the preview buffer, so that we always
    -- see the beginning of the file when we start previewing a new file
    vim.cmd('0')
  end)

  -- Because we are reusing the same preview buffer for different files, we
  -- need to clear the `bigfile` flag so that we can enable treesitter
  -- when previewing smaller files after previewing big files.
  vim.b[preview_buf].bigfile = nil

  preview_set_lines(preview_win)
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
    preview_request_last_timestamp = preview_request_last_timestamp + 1
    local current_request_timestamp = preview_request_last_timestamp
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
  callback = function(args)
    if vim.bo[args.buf].filetype ~= 'oil' then
      preview_finish()
    end
  end,
})

vim.api.nvim_create_autocmd('WinClosed', {
  desc = 'Close preview window when closing oil windows.',
  group = groupid_preview,
  callback = function(args)
    local win = tonumber(args.match)
    if win and preview_wins[win] then
      preview_finish(win)
    end
  end,
})

vim.api.nvim_create_autocmd({ 'WinResized', 'WinScrolled' }, {
  desc = 'Update invisible lines in preview buffer.',
  group = groupid_preview,
  callback = function(args)
    local wins = vim.tbl_map(
      function(win)
        return tonumber(win)
      end,
      vim.list_extend(
        { args.match },
        vim.v.event.windows or vim.tbl_keys(vim.v.event)
      )
    )

    for _, win in ipairs(wins) do
      preview_set_lines(win, args.event == 'WinScrolled')
    end
  end,
})

vim.api.nvim_create_autocmd('BufEnter', {
  desc = 'Update invisible lines in preview buffer.',
  group = groupid_preview,
  pattern = '*/oil_preview_\\d\\+://*',
  callback = function(args)
    preview_set_lines(vim.fn.bufwinid(args.buf), true)
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

-- Wrap original toggle function to update dir preview when hidden is set/unset
oil_view.toggle_hidden = (function(cb)
  return function(...)
    cb(...)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local path = vim.fn
        .bufname(vim.api.nvim_win_get_buf(win))
        :match('oil_preview_%d+://(.*)')
      if path and vim.fn.isdirectory(path) == 1 then
        preview_set_lines(win)
      end
    end
  end
end)(oil_view.toggle_hidden)

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
  watch_for_changes = true,
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
    ['gY'] = 'actions.copy_to_system_clipboard',
    ['gp'] = 'actions.paste_from_system_clipboard',
    -- Drag and drop
    -- Source: https://github.com/ndavd/dotfiles/blob/7af6efa64007c9e28ca5461c101034c2d5d53000/.config/nvim/lua/plugins/oil.lua#L15
    ['gd'] = {
      mode = { 'x', 'n' },
      buffer = true,
      desc = 'Drag and drop entry under the cursor',
      callback = function()
        local lnum_cur = vim.fn.line('.')
        local lnum_other = vim.fn.line('v')
        local entries = {}
        for lnum = math.min(lnum_cur, lnum_other), math.max(lnum_cur, lnum_other) do
          table.insert(entries, oil.get_entry_on_line(0, lnum))
        end
        local dir = oil.get_current_dir()
        if vim.tbl_isempty(entries) or not dir then
          return
        end
        if vim.fn.executable('dragon-drop') == 0 then
          vim.notify(
            '[oil.nvim] `dragon-drop` is not executable',
            vim.log.levels.WARN
          )
          return
        end
        vim.system({
          'dragon-drop',
          unpack(vim
            .iter(entries)
            :map(function(entry)
              return vim.fs.joinpath(dir, entry.name)
            end)
            :totable()),
        })
      end,
    },
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
        local entry_path =
          vim.fn.fnamemodify(vim.fs.joinpath(dir, entry.name), ':~')
        vim.fn.setreg('"', entry_path)
        vim.fn.setreg(vim.v.register, entry_path)
        vim.notify(
          string.format(
            "[oil.nvim] yanked '%s' to register '%s'",
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
  callback = function(args)
    vim.bo[args.buf].buflisted = false
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
  nested = true, -- fire `DirChanged` event
  callback = function(args)
    oil_cd(args.buf)
  end,
})

vim.api.nvim_create_autocmd('BufEnter', {
  desc = 'Record alternate file in dir buffers.',
  group = groupid,
  callback = function(args)
    local buf = args.buf
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
  callback = function(args)
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
    if vim.b[args.buf]._oil_entered == win then
      return
    end
    vim.b[args.buf]._oil_entered = win
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
      if
        not oil_config.view_options.show_hidden
        and oil_config.view_options.is_hidden_file(
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
        oil_view.toggle_hidden()
      end
      oil_view.set_last_cursor(parent_url, basename)
      oil_view.maybe_set_cursor()
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
  sethl(0, 'OilSecurityContext', { fg = 'Special' })
  sethl(0, 'OilSecurityExtended', { fg = 'Special' })
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

---Drag & drop files into oil buffer
---Source: https://github.com/HakonHarnes/img-clip.nvim/blob/main/plugin/img-clip.lua
vim.paste = (function(cb)
  return function(lines, phase)
    if vim.bo.ft ~= 'oil' then
      cb(lines, phase)
      return
    end

    -- Don't handle streamed and multi-line paste
    if phase ~= -1 or #lines ~= 1 then
      cb(lines, phase)
      return
    end

    local uri = lines[1]
    local fname = vim.fs.basename(uri:gsub('/+$', ''))
    vim.ui.input(
      { prompt = 'File name: ', completion = 'file', default = fname },
      function(input)
        fname = input
      end
    )
    if not fname then
      return
    end

    local buf = vim.api.nvim_get_current_buf()
    local current_dir = oil.get_current_dir()
    local dest = vim.fs.joinpath(current_dir, fname)

    ---Refresh oil buffer
    local function oil_refresh_place_cursor()
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      oil_view.render_buffer_async(buf, {}, function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        vim.api.nvim_buf_call(buf, function()
          oil_view.set_last_cursor(vim.api.nvim_buf_get_name(buf), fname)
          oil_view.maybe_set_cursor()
        end)
      end)
    end

    -- Paste file from web url
    if string.match(uri, '^https?://[^/]+/[^.]+') then
      require('utils.web').get(
        uri,
        dest,
        vim.schedule_wrap(function(o)
          if o.code ~= 0 then
            vim.notify(
              string.format(
                "[oil.nvim] failed to fetch from '%s': %s",
                uri,
                o.stderr
              ),
              vim.log.levels.WARN
            )
            return
          end
          oil_refresh_place_cursor()
        end)
      )
      return
    end

    -- Paste file from path
    local path = uri:gsub('^file://', '')
    vim.uv.fs_stat(path, function(_, stat)
      if not stat then
        vim.notify(
          string.format("[oil.nvim] invalid path: '%s'", path),
          vim.log.levels.WARN
        )
        return
      end

      require('oil.fs').recursive_copy(
        stat.type,
        path,
        dest,
        vim.schedule_wrap(function(err)
          if err then
            vim.notify(
              string.format(
                "[oil.nvim] failed to copy from '%s': %s",
                path,
                err
              ),
              vim.log.levels.WARN
            )
            return
          end
          oil_refresh_place_cursor()
        end)
      )
    end)
  end
end)(vim.paste)
