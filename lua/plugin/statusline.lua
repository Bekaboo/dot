local statusline = {}
local utils = require('utils')
local groupid = vim.api.nvim_create_augroup('StatusLine', {})

local diag_signs_default_text = { 'E', 'W', 'I', 'H' }

local diag_severity_map = {
  [1] = 'ERROR',
  [2] = 'WARN',
  [3] = 'INFO',
  [4] = 'HINT',
  ERROR = 1,
  WARN = 2,
  INFO = 3,
  HINT = 4,
}

---@param severity integer|string
---@return string
local function get_diag_sign_text(severity)
  local diag_config = vim.diagnostic.config()
  local signs_text = diag_config
    and diag_config.signs
    and type(diag_config.signs) == 'table'
    and diag_config.signs.text
  return signs_text
      and (signs_text[severity] or signs_text[diag_severity_map[severity]])
    or (
      diag_signs_default_text[severity]
      or diag_signs_default_text[diag_severity_map[severity]]
    )
end

-- stylua: ignore start
local modes = {
  ['n']      = 'NO',
  ['no']     = 'OP',
  ['nov']    = 'OC',
  ['noV']    = 'OL',
  ['no\x16'] = 'OB',
  ['\x16']   = 'VB',
  ['niI']    = 'IN',
  ['niR']    = 'RE',
  ['niV']    = 'RV',
  ['nt']     = 'NT',
  ['ntT']    = 'TM',
  ['v']      = 'VI',
  ['vs']     = 'VI',
  ['V']      = 'VL',
  ['Vs']     = 'VL',
  ['\x16s']  = 'VB',
  ['s']      = 'SE',
  ['S']      = 'SL',
  ['\x13']   = 'SB',
  ['i']      = 'IN',
  ['ic']     = 'IC',
  ['ix']     = 'IX',
  ['R']      = 'RE',
  ['Rc']     = 'RC',
  ['Rx']     = 'RX',
  ['Rv']     = 'RV',
  ['Rvc']    = 'RC',
  ['Rvx']    = 'RX',
  ['c']      = 'CO',
  ['cv']     = 'CV',
  ['r']      = 'PR',
  ['rm']     = 'PM',
  ['r?']     = 'P?',
  ['!']      = 'SH',
  ['t']      = 'TE',
}
-- stylua: ignore end

---Get string representation of the current mode
---@return string
function statusline.mode()
  local hl = vim.bo.mod and 'StatusLineHeaderModified' or 'StatusLineHeader'
  local mode = vim.fn.mode()
  local mode_str = (mode == 'n' and (vim.bo.ro or not vim.bo.ma)) and 'RO'
    or modes[mode]
  return utils.stl.hl(string.format(' %s ', mode_str), hl) .. ' '
end

---Get diff stats for current buffer
---@return string
function statusline.gitdiff()
  -- Integration with gitsigns.nvim
  ---@diagnostic disable-next-line: undefined-field
  local diff = vim.b.gitsigns_status_dict or utils.git.diffstat()
  local added = diff.added or 0
  local changed = diff.changed or 0
  local removed = diff.removed or 0
  if added == 0 and removed == 0 and changed == 0 then
    return ''
  end
  return string.format(
    '+%s~%s-%s',
    utils.stl.hl(tostring(added), 'StatusLineGitAdded'),
    utils.stl.hl(tostring(changed), 'StatusLineGitChanged'),
    utils.stl.hl(tostring(removed), 'StatusLineGitRemoved')
  )
end

---Get string representation of current git branch
---@return string
function statusline.branch()
  ---@diagnostic disable-next-line: undefined-field
  local branch = vim.b.gitsigns_status_dict and vim.b.gitsigns_status_dict.head
    or utils.git.branch()
  return branch == '' and '' or '#' .. utils.stl.escape(branch)
end

---Get current filetype
---@return string
function statusline.ft()
  return vim.bo.ft == '' and '' or vim.bo.ft:gsub('^%l', string.upper)
end

---@return string
function statusline.wordcount()
  local stats = nil
  local nwords, nchars = 0, 0 -- luacheck: ignore 311
  if
    vim.b.wc_words
    and vim.b.wc_chars
    and vim.b.wc_changedtick == vim.b.changedtick
  then
    nwords = vim.b.wc_words
    nchars = vim.b.wc_chars
  else
    stats = vim.fn.wordcount()
    nwords = stats.words
    nchars = stats.chars
    vim.b.wc_words = nwords
    vim.b.wc_chars = nchars
    vim.b.wc_changedtick = vim.b.changedtick
  end

  local vwords, vchars = 0, 0
  if vim.fn.mode():find('^[vsVS\x16\x13]') then
    stats = stats or vim.fn.wordcount()
    vwords = stats.visual_words
    vchars = stats.visual_chars
  end

  if nwords == 0 and nchars == 0 then
    return ''
  end

  return string.format(
    '%s%d word%s, %s%d char%s',
    vwords > 0 and vwords .. '/' or '',
    nwords,
    nwords > 1 and 's' or '',
    vchars > 0 and vchars .. '/' or '',
    nchars,
    nchars > 1 and 's' or ''
  )
end

---Record file name of normal buffers, key:val = fname:buffers_with_fname
---@type table<string, number[]>
local fnames = {}

---Update path diffs for buffers with the same file name
---@param bufs integer[]
---@return nil
local function update_pdiffs(bufs)
  bufs = vim.tbl_filter(vim.api.nvim_buf_is_valid, bufs)

  for i, path_diff in
    ipairs(vim.tbl_filter(function(d)
      return d ~= ''
    end, utils.fs.diff(vim.tbl_map(vim.api.nvim_buf_get_name, bufs))))
  do
    local _buf = bufs[i]
    vim.b[_buf]._stl_pdiff = path_diff
  end
end

---Add a normal buffer to `fnames`, calc diff for buffer with non-unique
---file names
---@param buf integer buffer number
---@return nil
local function add_buf(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].bt ~= '' then
    return
  end

  local fname = vim.fs.basename(vim.api.nvim_buf_get_name(buf))
  if fname == '' then
    return
  end

  if not fnames[fname] then
    fnames[fname] = {}
  end

  local bufs = fnames[fname] -- buffers with the same name as the removed buf
  table.insert(bufs, buf)

  update_pdiffs(bufs)
end

for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  add_buf(buf)
end

vim.api.nvim_create_autocmd({ 'BufAdd', 'BufFilePost' }, {
  group = groupid,
  desc = 'Track new buffer file name.',
  callback = function(info)
    -- Delay adding buffer to fnames to ensure attributes, e.g.
    -- `bt`, are set for special buffers, for example, terminal buffers
    vim.schedule(function()
      add_buf(info.buf)
    end)
  end,
})

vim.api.nvim_create_autocmd({ 'BufDelete', 'BufFilePre' }, {
  group = groupid,
  desc = 'Remove deleted buffer file name from record.',
  callback = function(info)
    if vim.bo[info.buf].bt ~= '' then
      return
    end

    local fname = vim.fs.basename(vim.api.nvim_buf_get_name(info.buf))
    local bufs = fnames[fname] -- buffers with the same name as the removed buf
    if not bufs then
      return
    end

    for i, buf in ipairs(bufs) do
      if buf == info.buf then
        table.remove(bufs, i)
        break
      end
    end

    local num_bufs = #bufs
    if num_bufs == 0 then
      fnames[fname] = nil
      return
    end

    if num_bufs == 1 then
      vim.b[bufs[1]]._stl_pdiff = nil
      return
    end

    -- Still have multiple buffers with the same file name,
    -- update path diffs for the remaining buffers
    update_pdiffs(bufs)
  end,
})

function statusline.fname()
  local bname = vim.api.nvim_buf_get_name(0)

  -- Normal buffer
  if vim.bo.bt == '' then
    -- Unnamed normal buffer
    if bname == '' then
      return '[Buffer %n]'
    end
    -- Named normal buffer, show file name, if the file name is not unique,
    -- show local cwd (often project root) after the file name
    local fname = vim.fs.basename(bname)
    if vim.b._stl_pdiff then
      return string.format(
        '%s [%s]',
        utils.stl.escape(fname),
        vim.b._stl_pdiff
      )
    end
    return utils.stl.escape(fname)
  end

  -- Terminal buffer, show terminal command and id
  if vim.bo.bt == 'terminal' then
    local id, cmd = bname:match('^term://.*/(%d+):(.*)')
    return id
        and cmd
        and string.format('[Terminal] %s (%s)', utils.stl.escape(cmd), id)
      or '[Terminal] %F'
  end

  -- Other special buffer types
  local prefix, suffix = bname:match('^%s*(%S+)://(.*)')
  if prefix and suffix then
    return string.format(
      '[%s] %s',
      utils.stl.escape(utils.string.snake_to_camel(prefix)),
      utils.stl.escape(suffix)
    )
  end

  return '%F'
end

---Text filetypes
---@type table<string, true>
local ft_text = {
  [''] = true,
  ['tex'] = true,
  ['markdown'] = true,
  ['text'] = true,
}

---Additional info for the current buffer enclosed in parentheses
---@return string
function statusline.info()
  if vim.bo.bt ~= '' then
    return ''
  end
  local info = {}
  ---@param section string
  local function add_section(section)
    if section ~= '' then
      table.insert(info, section)
    end
  end
  add_section(statusline.ft())
  if ft_text[vim.bo.ft] and not vim.b.bigfile then
    add_section(statusline.wordcount())
  end
  add_section(statusline.branch())
  add_section(statusline.gitdiff())
  return vim.tbl_isempty(info) and ''
    or string.format('(%s) ', table.concat(info, ', '))
end

vim.api.nvim_create_autocmd('DiagnosticChanged', {
  group = groupid,
  desc = 'Update diagnostics cache for the status line.',
  callback = function(info)
    vim.b[info.buf].diag_cnt_cache = vim.diagnostic.count(info.buf)
    vim.b[info.buf].diag_str_cache = nil
  end,
})

---Get string representation of diagnostics for current buffer
---@return string
function statusline.diag()
  if vim.b.diag_str_cache then
    return vim.b.diag_str_cache
  end
  local str = ''
  local buf_cnt = vim.b.diag_cnt_cache or {}
  for serverity_nr, severity in ipairs({ 'Error', 'Warn', 'Info', 'Hint' }) do
    local cnt = buf_cnt[serverity_nr] ~= vim.NIL and buf_cnt[serverity_nr] or 0
    if cnt > 0 then
      local icon_text = get_diag_sign_text(serverity_nr)
      local icon_hl = 'StatusLineDiagnostic' .. severity
      str = str
        .. (str == '' and '' or ' ')
        .. utils.stl.hl(icon_text, icon_hl)
        .. cnt
    end
  end
  if str:find('%S') then
    str = str .. ' '
  end
  vim.b.diag_str_cache = str
  return str
end

local spinner_end_keep = 2000 -- ms
local spinner_status_keep = 600 -- ms
local spinner_progress_keep = 80 -- ms
local spinner_timer = vim.uv.new_timer()

local spinner_icons ---@type string[]
local spinner_icon_done ---@type string

if vim.g.nf then
  spinner_icon_done = vim.trim(utils.static.icons.Ok)
  spinner_icons = {
    '⣷',
    '⣯',
    '⣟',
    '⡿',
    '⢿',
    '⣻',
    '⣽',
    '⣾',
  }
else
  spinner_icon_done = '[done]'
  spinner_icons = {
    '[    ]',
    '[=   ]',
    '[==  ]',
    '[=== ]',
    '[ ===]',
    '[  ==]',
    '[   =]',
  }
end

---Id and additional info of language servers in progress
---@type table<integer, { name: string, timestamp: integer, type: 'begin'|'report'|'end' }>
local server_info = {}

vim.api.nvim_create_autocmd('LspProgress', {
  desc = 'Update LSP progress info for the status line.',
  group = groupid,
  callback = function(info)
    if spinner_timer then
      spinner_timer:start(
        spinner_progress_keep,
        spinner_progress_keep,
        vim.schedule_wrap(vim.cmd.redrawstatus)
      )
    end

    local id = info.data.client_id
    local now = vim.uv.now()
    server_info[id] = {
      name = vim.lsp.get_client_by_id(id).name,
      timestamp = now,
      type = info.data
        and info.data.params
        and info.data.params.value
        and info.data.params.value.kind,
    } -- Update LSP progress data
    -- Clear client message after a short time if no new message is received
    vim.defer_fn(function()
      -- No new report since the timer was set
      local last_timestamp = (server_info[id] or {}).timestamp
      if not last_timestamp or last_timestamp == now then
        server_info[id] = nil
        if vim.tbl_isempty(server_info) and spinner_timer then
          spinner_timer:stop()
        end
        vim.cmd.redrawstatus()
      end
    end, spinner_end_keep)
  end,
})

---@return string
function statusline.lsp_progress()
  if vim.tbl_isempty(server_info) then
    return ''
  end

  local buf = vim.api.nvim_get_current_buf()
  local server_ids = {}
  for id, _ in pairs(server_info) do
    if vim.tbl_contains(vim.lsp.get_buffers_by_client_id(id), buf) then
      table.insert(server_ids, id)
    end
  end
  if vim.tbl_isempty(server_ids) then
    return ''
  end

  local now = vim.uv.now()
  ---@return boolean
  local function allow_changing_state()
    return not vim.b.spinner_state_changed
      or now - vim.b.spinner_state_changed > spinner_status_keep
  end

  if #server_ids == 1 and server_info[server_ids[1]].type == 'end' then
    if vim.b.spinner_icon ~= spinner_icon_done and allow_changing_state() then
      vim.b.spinner_state_changed = now
      vim.b.spinner_icon = spinner_icon_done
    end
  else
    local spinner_icon_progress = spinner_icons[math.ceil(
      now / spinner_progress_keep
    ) % #spinner_icons + 1]
    if vim.b.spinner_icon ~= spinner_icon_done then
      vim.b.spinner_icon = spinner_icon_progress
    elseif allow_changing_state() then
      vim.b.spinner_state_changed = now
      vim.b.spinner_icon = spinner_icon_progress
    end
  end

  return string.format(
    '%s %s ',
    table.concat(
      vim.tbl_map(function(id)
        return utils.stl.escape(server_info[id].name)
      end, server_ids),
      ', '
    ),
    vim.b.spinner_icon
  )
end

-- stylua: ignore start
---Statusline components
---@type table<string, string>
local components = {
  align        = [[%=]],
  flag         = [[%{%&bt==#''?'':(&bt==#'help'?'%h ':(&pvw?'%w ':''))%}]],
  diag         = [[%{%v:lua.require'plugin.statusline'.diag()%}]],
  fname        = [[%{%v:lua.require'plugin.statusline'.fname()%} ]],
  info         = [[%{%v:lua.require'plugin.statusline'.info()%}]],
  lsp_progress = [[%{%v:lua.require'plugin.statusline'.lsp_progress()%}]],
  mode         = [[%{%v:lua.require'plugin.statusline'.mode()%}]],
  padding      = [[ ]],
  pos          = [[%{%&ru?"%l:%c ":""%}]],
  truncate     = [[%<]],
}
-- stylua: ignore end

local stl = table.concat({
  components.mode,
  components.flag,
  components.fname,
  components.info,
  components.align,
  components.truncate,
  components.lsp_progress,
  components.diag,
  components.pos,
})

local stl_nc = table.concat({
  components.padding,
  components.flag,
  components.fname,
  components.align,
  components.truncate,
  components.pos,
})

---Get statusline string
---@return string
function statusline.get()
  return vim.g.statusline_winid == vim.api.nvim_get_current_win() and stl
    or stl_nc
end

vim.api.nvim_create_autocmd(
  { 'FileChangedShellPost', 'DiagnosticChanged', 'LspProgress' },
  {
    group = groupid,
    command = 'silent! redrawstatus',
  }
)

---Set default highlight groups for statusline components
---@return  nil
local function set_default_hlgroups()
  local default_attr = utils.hl.get(0, {
    name = 'StatusLine',
    link = false,
    winhl_link = false,
  })

  ---@param hlgroup_name string
  ---@param attr table
  ---@return nil
  local function sethl(hlgroup_name, attr)
    local merged_attr = vim.tbl_deep_extend('keep', attr, default_attr)
    utils.hl.set_default(0, hlgroup_name, merged_attr)
  end
  sethl('StatusLineGitAdded', { fg = 'GitSignsAdd' })
  sethl('StatusLineGitChanged', { fg = 'GitSignsChange' })
  sethl('StatusLineGitRemoved', { fg = 'GitSignsDelete' })
  sethl('StatusLineDiagnosticHint', { fg = 'DiagnosticSignHint' })
  sethl('StatusLineDiagnosticInfo', { fg = 'DiagnosticSignInfo' })
  sethl('StatusLineDiagnosticWarn', { fg = 'DiagnosticSignWarn' })
  sethl('StatusLineDiagnosticError', { fg = 'DiagnosticSignError' })
  sethl('StatusLineHeader', { fg = 'TabLine', bg = 'fg', reverse = true })
  sethl('StatusLineHeaderModified', {
    fg = 'Special',
    bg = 'fg',
    reverse = true,
  })
end
set_default_hlgroups()

vim.api.nvim_create_autocmd('ColorScheme', {
  group = groupid,
  callback = set_default_hlgroups,
})

return statusline
