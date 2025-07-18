vim.g.has_ui = #vim.api.nvim_list_uis() > 0
vim.g.has_gui = vim.fn.has('gui_running') == 1
vim.g.has_display = vim.g.has_ui and vim.env.DISPLAY ~= nil
vim.g.has_nf = vim.env.TERM ~= 'linux' and vim.env.NVIM_NF and true or false

vim.opt.exrc = true
vim.opt.confirm = true
vim.opt.timeout = false
vim.opt.textwidth = 79
vim.opt.colorcolumn = '+1'
vim.opt.cursorlineopt = 'number'
vim.opt.cursorline = true
vim.opt.helpheight = 10
vim.opt.showmode = false
vim.opt.mousemoveevent = true
vim.opt.number = true
vim.opt.ruler = true
vim.opt.pumheight = 16
vim.opt.scrolloff = 2
vim.opt.sidescrolloff = 8
vim.opt.signcolumn = 'yes:1'
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.swapfile = false
vim.opt.undofile = true
vim.opt.wrap = false
vim.opt.linebreak = true
vim.opt.breakindent = true
vim.opt.smoothscroll = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.completeopt = 'menuone'
vim.opt.selection = 'old'
vim.opt.tabclose = 'uselast'

-- Defer shada reading
local shada_augroup = vim.api.nvim_create_augroup('OptShada', {})

---Restore 'shada' option and read from shada once
local function rshada()
  pcall(vim.api.nvim_del_augroup_by_id, shada_augroup)

  vim.opt.shada = vim.api.nvim_get_option_info2('shada', {}).default
  pcall(vim.cmd.rshada)
end

vim.opt.shada = ''
vim.api.nvim_create_autocmd('BufReadPre', {
  group = shada_augroup,
  once = true,
  callback = rshada,
})
vim.api.nvim_create_autocmd('UIEnter', {
  group = shada_augroup,
  once = true,
  callback = vim.schedule_wrap(rshada),
})

-- Folding
vim.opt.foldlevelstart = 99
vim.opt.foldtext = ''
vim.opt.foldmethod = 'indent'
vim.opt.foldopen:remove('block') -- make `{`/`}` skip over folds

-- Enable treesitter folding
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('TSFolding', {}),
  desc = 'Set treesitter folding.',
  -- Schedule to wait treesitter highlighter to attach
  callback = vim.schedule_wrap(function(args)
    local buf = args.buf
    if not require('utils.ts').is_active(buf) then
      return
    end

    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      local wo = vim.wo[win]
      if wo.foldexpr == '0' then
        wo[0].foldexpr = 'v:lua.vim.treesitter.foldexpr()'
        if wo.foldmethod == 'indent' or wo.foldmethod == 'manual' then
          wo[0].foldmethod = 'expr'
        end
      end
    end
  end),
})

-- Recognize numbered lists when formatting text and
-- continue comments on new lines
--
-- Don't auto-wrap non-comment text by default
vim.opt.formatoptions:append('normc')
vim.opt.formatoptions:remove('t')

-- Treat number as signed/unsigned based on preceding whitespaces when
-- incrementing/decrementing numbers
vim.opt.nrformats:append('blank')

-- Spell check
vim.opt.spellsuggest = 'best,9'
vim.opt.spellcapcheck = ''
vim.opt.spelllang = 'en,cjk'
vim.opt.spelloptions = 'camel'

local spell_augroup = vim.api.nvim_create_augroup('OptSpell', {})

---Set spell check options
---@return nil
local function spellcheck()
  pcall(vim.api.nvim_del_augroup_by_id, spell_augroup)

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if not require('utils.opt').spell:was_locally_set({ win = win }) then
      vim.api.nvim_win_call(win, function()
        vim.opt.spell = true
      end)
    end
  end
end

vim.api.nvim_create_autocmd('FileType', {
  group = spell_augroup,
  once = true,
  callback = function()
    local ts_start = vim.treesitter.start
    function vim.treesitter.start(...) ---@diagnostic disable-line: duplicate-set-field
      -- Ensure spell check settings are set before starting treesitter
      -- to avoid highlighting `@nospell` nodes
      spellcheck()
      vim.treesitter.start = ts_start
      return vim.treesitter.start(...)
    end
  end,
})

vim.api.nvim_create_autocmd('UIEnter', {
  group = spell_augroup,
  once = true,
  callback = vim.schedule_wrap(spellcheck),
})

-- Cursor shape
vim.opt.gcr = {
  'i-c-ci-ve:blinkoff500-blinkon500-block-TermCursor',
  'n-v:block-Curosr/lCursor',
  'o:hor50-Curosr/lCursor',
  'r-cr:hor20-Curosr/lCursor',
}

-- Use histogram algorithm for diffing, generates more readable diffs in
-- situations where two lines are swapped
vim.opt.diffopt:append({
  'algorithm:histogram',
  'indent-heuristic',
  'linematch:60',
})

-- Use system clipboard
vim.api.nvim_create_autocmd('UIEnter', {
  once = true,
  callback = vim.schedule_wrap(function()
    vim.opt.clipboard:append('unnamedplus')
  end),
})

-- Align columns in quickfix window
vim.opt.quickfixtextfunc = [[v:lua.require'utils.opts'.qftf]]

---@param args table
---@return string[]
function _G._qftf(args)
  local qflist = args.quickfix == 1
      and vim.fn.getqflist({ id = args.id, items = 0 }).items
    or vim.fn.getloclist(args.winid, { id = args.id, items = 0 }).items

  if vim.tbl_isempty(qflist) then
    return {}
  end

  local fname_str_cache = {}
  local lnum_str_cache = {}
  local col_str_cache = {}
  local type_str_cache = {}
  local nr_str_cache = {}

  local fname_width_cache = {}
  local lnum_width_cache = {}
  local col_width_cache = {}
  local type_width_cache = {}
  local nr_width_cache = {}

  ---Traverse the qflist and get the maximum display width of the
  ---transformed string; cache the transformed string and its width
  ---in table `str_cache` and `width_cache` respectively
  ---@param trans fun(item: table): string|number
  ---@param max_width_allowed integer?
  ---@param str_cache table
  ---@param width_cache table
  ---@return integer
  local function _traverse(trans, max_width_allowed, str_cache, width_cache)
    max_width_allowed = max_width_allowed or math.huge
    local max_width_seen = 0
    for i, item in ipairs(qflist) do
      local str = tostring(trans(item))
      local width = vim.fn.strdisplaywidth(str)
      str_cache[i] = str
      width_cache[i] = width
      if width > max_width_seen then
        max_width_seen = width
      end
    end
    return math.min(max_width_allowed, max_width_seen)
  end

  ---@param item table
  ---@return string
  local function _fname_trans(item)
    local bufnr = item.bufnr
    local module = item.module
    local filename = item.filename
    return module and module ~= '' and module
      or filename and filename ~= '' and filename
      or vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':~:.')
  end

  ---@param item table
  ---@return string|integer
  local function _lnum_trans(item)
    if item.lnum == item.end_lnum or item.end_lnum == 0 then
      return item.lnum
    end
    return string.format('%s-%s', item.lnum, item.end_lnum)
  end

  ---@param item table
  ---@return string|integer
  local function _col_trans(item)
    if item.col == item.end_col or item.end_col == 0 then
      return item.col
    end
    return string.format('%s-%s', item.col, item.end_col)
  end

  local type_sign_map = {
    E = 'ERROR',
    W = 'WARN',
    I = 'INFO',
    N = 'HINT',
  }

  ---@param item table
  ---@return string
  local function _type_trans(item)
    -- Sometimes `item.type` will contain unprintable characters,
    -- e.g. items in the qflist of `:helpg vim`
    local type = (type_sign_map[item.type] or item.type):gsub('[^%g]', '')
    return type == '' and '' or ' ' .. type
  end

  ---@param item table
  ---@return string
  local function _nr_trans(item)
    return item.nr <= 0 and '' or ' ' .. item.nr
  end

  -- stylua: ignore start
  local max_width = math.ceil(vim.go.columns / 2)
  local fname_width = _traverse(_fname_trans, max_width, fname_str_cache, fname_width_cache)
  local lnum_width = _traverse(_lnum_trans, max_width, lnum_str_cache, lnum_width_cache)
  local col_width = _traverse(_col_trans, max_width, col_str_cache, col_width_cache)
  local type_width = _traverse(_type_trans, max_width, type_str_cache, type_width_cache)
  local nr_width = _traverse(_nr_trans, max_width, nr_str_cache, nr_width_cache)
  -- stylua: ignore end

  local lines = {} ---@type string[]
  local format_str = vim.go.termguicolors and '%s %s:%s%s%s %s'
    or '%s│%s:%s%s%s│ %s'

  local function _fill_item(idx, item)
    local fname = fname_str_cache[idx]
    local fname_cur_width = fname_width_cache[idx]

    if item.lnum == 0 and item.col == 0 and item.text == '' then
      table.insert(lines, fname)
      return
    end

    local lnum = lnum_str_cache[idx]
    local col = col_str_cache[idx]
    local type = type_str_cache[idx]
    local nr = nr_str_cache[idx]

    local lnum_cur_width = lnum_width_cache[idx]
    local col_cur_width = col_width_cache[idx]
    local type_cur_width = type_width_cache[idx]
    local nr_cur_width = nr_width_cache[idx]

    table.insert(
      lines,
      string.format(
        format_str,
        -- Do not use `string.format()` here because it only allows
        -- at most 99 characters for alignment and alignment is
        -- based on byte length instead of display length
        fname .. string.rep(' ', fname_width - fname_cur_width),
        string.rep(' ', lnum_width - lnum_cur_width) .. lnum,
        col .. string.rep(' ', col_width - col_cur_width),
        type .. string.rep(' ', type_width - type_cur_width),
        nr .. string.rep(' ', nr_width - nr_cur_width),
        item.text
      )
    )
  end

  for i, item in ipairs(qflist) do
    _fill_item(i, item)
  end

  return lines
end

vim.opt.backup = true
vim.opt.backupdir:remove('.')

vim.opt.list = true
vim.opt.listchars = {
  tab = '  ',
  trail = '·',
}
vim.opt.fillchars = {
  fold = '·',
  foldsep = ' ',
  eob = ' ',
}

if vim.g.has_nf then
  vim.opt.fillchars:append({
    foldopen = '',
    foldclose = '',
  })
else
  vim.opt.fillchars:append({
    foldopen = 'v',
    foldclose = '>',
  })
end

vim.api.nvim_create_autocmd('UIEnter', {
  once = true,
  callback = function()
    if vim.opt.termguicolors:get() then
      vim.opt.listchars:append({ nbsp = '␣' })
      vim.opt.fillchars:append({ diff = '╱' })
    end
  end,
})

-- Netrw settings
vim.g.netrw_banner = 0
vim.g.netrw_cursor = 5
vim.g.netrw_keepdir = 0
vim.g.netrw_keepj = ''
vim.g.netrw_list_hide = [[\(^\|\s\s\)\zs\.\S\+]]
vim.g.netrw_liststyle = 1
vim.g.netrw_localcopydircmd = 'cp -r'

-- Fzf settings
vim.g.fzf_layout = {
  window = {
    width = 0.8,
    height = 0.8,
    pos = 'center',
  },
}
vim.env.FZF_DEFAULT_OPTS = (vim.env.FZF_DEFAULT_OPTS or '')
  .. ' --border=sharp --margin=0 --padding=0'

-- Disable plugins shipped with nvim
vim.g.loaded_2html_plugin = 0
vim.g.loaded_gzip = 0
vim.g.loaded_matchit = 0
vim.g.loaded_spellfile_plugin = 0
vim.g.loaded_tar = 0
vim.g.loaded_tarPlugin = 0
vim.g.loaded_tutor_mode_plugin = 0
vim.g.loaded_zip = 0
vim.g.loaded_zipPlugin = 0

---Lazy-load runtime files
---@param runtime string
---@param flag string
---@param events string|string[]
local function load(runtime, flag, events)
  if vim.g[flag] and vim.g[flag] ~= 0 then
    return
  end

  vim.g[flag] = 0
  if type(events) ~= 'table' then
    events = { events }
  end

  local gid = vim.api.nvim_create_augroup('Load_' .. runtime, {})
  for _, e in
    ipairs(vim.tbl_map(function(e)
      return vim.split(e, ' ', {
        trimempty = true,
        plain = true,
      })
    end, events))
  do
    vim.api.nvim_create_autocmd(e[1], {
      once = true,
      pattern = e[2],
      group = gid,
      callback = function()
        if vim.g[flag] == 0 then
          vim.g[flag] = nil
          vim.cmd.runtime(runtime)
        end
        vim.api.nvim_del_augroup_by_id(gid)
      end,
    })
  end
end

load('plugin/rplugin.vim', 'loaded_remote_plugins', {
  'FileType',
  'BufNew',
  'BufWritePost',
  'BufReadPre',
  'CmdUndefined UpdateRemotePlugins',
})
load('provider/python3.vim', 'loaded_python3_provider', {
  'FileType python',
  'BufNew *.py,*.ipynb',
  'BufEnter *.py,*.ipynb',
  'BufWritePost *.py,*.ipynb',
  'BufReadPre *.py,*.ipynb',
})

-- Fix treesitter bug: when `vim.treesitter.start/stop` is called with a
-- different `buf` from current buffer, it can affect current buffer's
-- language tree
-- TODO: report to upstream
vim.api.nvim_create_autocmd('FileType', {
  once = true,
  callback = function()
    local function ts_buf_call_wrap(cb)
      return function(buf, ...)
        if buf and not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        local args = { ... }
        vim.api.nvim_buf_call(buf or 0, function()
          cb(buf, unpack(args))
        end)
      end
    end

    vim.treesitter.start = ts_buf_call_wrap(vim.treesitter.start)
    vim.treesitter.stop = ts_buf_call_wrap(vim.treesitter.stop)
  end,
})
