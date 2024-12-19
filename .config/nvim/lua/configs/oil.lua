local oil = require('oil')
local icons = require('utils.static').icons
local icon_file = vim.trim(icons.File)
local icon_dir = vim.trim(icons.Folder)

local preview_wins = {} ---@type table<integer, integer>
local preview_bufs = {} ---@type table<integer, integer>
local preview_max_fsize = 1000000
local preview_debounce = 64 -- ms
local preview_request_last_timestamp = 0

---Change window-local directory to `dir`
---@param dir string
---@return nil
local function lcd(dir)
  local ok = pcall(vim.cmd.lcd, dir)
  if not ok then
    vim.notify('[oil.nvim] failed to cd to ' .. dir, vim.log.levels.WARN)
  end
end

---Generate lines for preview window when preview is not available
---@param msg string
---@param height integer
---@param width integer
---@return string[]
local function nopreview(msg, height, width)
  local lines = {}
  local fillchar = vim.opt_local.fillchars:get().diff or '-'
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

---End preview for oil window `win`
---Close preview window and delete preview buffer
---@param oil_win? integer oil window ID
---@return nil
local function end_preview(oil_win)
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

---Preview file under cursor in a split
---@return nil
local function preview()
  local entry = oil.get_cursor_entry()
  local fname = entry and entry.name
  local dir = oil.get_current_dir()
  if not dir or not fname then
    return
  end
  local fpath = vim.fs.joinpath(dir, fname)
  local stat = vim.uv.fs_stat(fpath)
  if not stat or (stat.type ~= 'file' and stat.type ~= 'directory') then
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
    vim.opt_local.spell = false
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
    vim.opt_local.signcolumn = 'no'
    vim.opt_local.foldcolumn = '0'
    vim.opt_local.winbar = ''
    vim.api.nvim_set_current_win(oil_win)
  end
  ---Edit corresponding file in oil preview buffer
  ---@return nil
  local function _edit_preview()
    local cursor = vim.api.nvim_win_get_cursor(0)
    vim.cmd.edit(fpath)
    end_preview(oil_win)
    pcall(vim.api.nvim_win_set_cursor, 0, cursor)
  end
  -- Set keymap for opening the file from preview buffer
  vim.keymap.set('n', '<CR>', _edit_preview, { buffer = preview_buf })
  vim.api.nvim_create_autocmd('BufReadCmd', {
    desc = 'Edit corresponding file in oil preview buffers.',
    group = vim.api.nvim_create_augroup('OilPreviewEdit', {}),
    buffer = preview_buf,
    callback = vim.schedule_wrap(_edit_preview),
  })
  -- Preview buffer already contains contents of file to preview
  local preview_bufname = vim.fn.bufname(preview_buf)
  local preview_bufnewname = 'oil_preview://' .. fpath
  if preview_bufname == preview_bufnewname then
    return
  end
  local preview_win_height = vim.api.nvim_win_get_height(preview_win)
  local preview_win_width = vim.api.nvim_win_get_width(preview_win)
  local add_syntax = false
  local lines = stat.type == 'directory'
      and vim.fn.systemlist('ls -lhA ' .. vim.fn.shellescape(fpath))
    or stat.size == 0 and nopreview(
      'Empty file',
      preview_win_height,
      preview_win_width
    )
    or stat.size > preview_max_fsize and nopreview(
      'File too large to preview',
      preview_win_height,
      preview_win_width
    )
    or not vim.fn.system({ 'file', fpath }):match('text') and nopreview(
      'Binary file, no preview available',
      preview_win_height,
      preview_win_width
    )
    or (function()
        add_syntax = true
        return true
      end)()
      and vim
        .iter(io.lines(fpath))
        :map(function(line)
          return (line:gsub('\x0d$', ''))
        end)
        :totable()
  do
    vim.bo[preview_buf].modifiable = true
    vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines)
    vim.bo[preview_buf].modifiable = false
  end
  vim.api.nvim_buf_set_name(preview_buf, preview_bufnewname)
  -- If previewing a directory, change cwd to that directory
  -- so that we can `gf` to files in the preview buffer;
  -- else change cwd to the parent directory of the file in preview
  vim.api.nvim_win_call(preview_win, function()
    local target_dir = stat.type == 'directory' and fpath or dir
    if vim.fn.getcwd(0) ~= target_dir then
      lcd(target_dir)
    end
    -- Move cursor to the first line of the preview buffer, so that we always
    -- see the beginning of the file when we start previewing a new file
    vim.cmd('0')
  end)
  vim.api.nvim_buf_call(preview_buf, function()
    vim.treesitter.stop(preview_buf)
  end)
  vim.bo[preview_buf].syntax = ''
  if not add_syntax then
    return
  end
  local ft = vim.filetype.match({
    buf = preview_buf,
    filename = fpath,
  })
  if ft and not pcall(vim.treesitter.start, preview_buf, ft) then
    vim.bo[preview_buf].syntax = ft
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
      end_preview()
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
      end_preview()
    end
  end,
})
vim.api.nvim_create_autocmd('WinClosed', {
  desc = 'Close preview window when closing oil windows.',
  group = groupid_preview,
  callback = function(info)
    local win = tonumber(info.match)
    if win and preview_wins[win] then
      end_preview(win)
    end
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
    end_preview()
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
    { 'size', highlight = 'Special' },
    { 'mtime', highlight = 'Number' },
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
    number = false,
    relativenumber = false,
    signcolumn = 'no',
    foldcolumn = '0',
    statuscolumn = '',
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

vim.api.nvim_create_autocmd({ 'BufEnter', 'TextChanged' }, {
  desc = 'Set cwd to follow directory shown in oil buffers.',
  group = groupid,
  pattern = 'oil://*',
  callback = function(info)
    if vim.bo[info.buf].filetype == 'oil' then
      local cwd = vim.fs.normalize(vim.fn.getcwd(vim.fn.winnr()))
      local oildir = vim.fs.normalize(oil.get_current_dir())
      if cwd ~= oildir and vim.uv.fs_stat(oildir) then
        lcd(oildir)
      end
    end
  end,
})

vim.api.nvim_create_autocmd('BufEnter', {
  desc = 'Record alternate file in dir buffers.',
  group = groupid,
  callback = function(info)
    local buf = info.buf
    local bufname = vim.api.nvim_buf_get_name(buf)
    if (vim.uv.fs_stat(bufname) or {}).type == 'directory' then
      vim.b[buf]._alt_file = vim.fn.bufnr('#')
    end
  end,
})

vim.api.nvim_create_autocmd('BufEnter', {
  desc = 'Set last cursor position in oil buffers when editing parent dir.',
  group = groupid,
  pattern = 'oil://*',
  callback = function()
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
  sethl(0, 'OilLinkTarget', { fg = 'Comment' })
  sethl(0, 'OilCopy', { fg = 'DiagnosticSignHint', bold = true })
  sethl(0, 'OilMove', { fg = 'DiagnosticSignWarn', bold = true })
  sethl(0, 'OilChange', { fg = 'DiagnosticSignWarn', bold = true })
  sethl(0, 'OilCreate', { fg = 'DiagnosticSignInfo', bold = true })
  sethl(0, 'OilDelete', { fg = 'DiagnosticSignError', bold = true })
  sethl(0, 'OilPermissionNone', { fg = 'NonText' })
  sethl(0, 'OilPermissionRead', { fg = 'DiagnosticSignWarn' })
  sethl(0, 'OilPermissionWrite', { fg = 'DiagnosticSignError' })
  sethl(0, 'OilPermissionExecute', { fg = 'DiagnosticSignInfo' })
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
