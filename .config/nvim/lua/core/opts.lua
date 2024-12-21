vim.g.has_ui = #vim.api.nvim_list_uis() > 0
vim.g.has_gui = vim.fn.has('gui_running') == 1
vim.g.has_display = vim.g.has_ui and vim.env.DISPLAY ~= nil
vim.g.has_nf = vim.env.TERM ~= 'linux' and vim.env.NVIM_NF and true or false

vim.opt.confirm = true
vim.opt.timeout = false
vim.opt.colorcolumn = '+1'
vim.opt.cursorlineopt = 'number'
vim.opt.cursorline = true
vim.opt.helpheight = 10
vim.opt.showmode = false
vim.opt.mousemoveevent = true
vim.opt.number = true
vim.opt.ruler = true
vim.opt.pumheight = 16
vim.opt.scrolloff = 4
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
vim.opt.jumpoptions = 'stack,view'

-- Defer shada reading
local shada_read ---@boolean?

---Restore 'shada' option and read from shada once
---@return true
local function rshada()
  if shada_read then
    return true
  end
  shada_read = true

  vim.cmd.set('shada&')
  pcall(vim.cmd.rshada)
  return true
end

vim.opt.shada = ''
vim.api.nvim_create_autocmd('BufReadPre', { once = true, callback = rshada })
vim.api.nvim_create_autocmd('UIEnter', {
  once = true,
  callback = function()
    vim.schedule(rshada)
    return true
  end,
})

-- Folding
vim.opt.foldlevelstart = 99
vim.opt.foldtext = ''
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('TSFolding', {}),
  desc = 'Set treesitter folding.',
  callback = function(info)
    local buf = info.buf
    local utils = require('utils')
    if not utils.treesitter.is_active(buf) then
      return
    end

    vim.api.nvim_buf_call(buf, function()
      if not utils.opt.fdm:last_set_loc() then
        vim.opt_local.fdm = 'expr'
      end
      if not utils.opt.fde:last_set_loc() then
        vim.opt_local.fde = 'v:lua.vim.treesitter.foldexpr()'
      end
    end)
  end,
})

-- Recognize numbered lists when formatting text
vim.opt.formatoptions:append('n')

-- Spell check
local spellcheck_set

---Set spell check options
---@return nil
local function spellcheck()
  if spellcheck_set ~= nil then
    return
  end
  spellcheck_set = true

  vim.opt.spell = true
  vim.opt.spellcapcheck = ''
  vim.opt.spelllang = 'en,cjk'
  vim.opt.spelloptions = 'camel'
  vim.opt.spellsuggest = 'best,9'
end

vim.api.nvim_create_autocmd('FileType', {
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
    return true
  end,
})

vim.api.nvim_create_autocmd('UIEnter', {
  once = true,
  callback = function()
    vim.schedule(spellcheck)
    return true
  end,
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
})

-- Use system clipboard
vim.api.nvim_create_autocmd('UIEnter', {
  once = true,
  callback = function()
    vim.schedule(function()
      vim.opt.clipboard:append('unnamedplus')
    end)
    return true
  end,
})

-- Align columns in quickfix window
vim.opt.quickfixtextfunc = [[v:lua.require'utils.misc'.qftf]]

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
end

vim.api.nvim_create_autocmd('UIEnter', {
  once = true,
  callback = function()
    if vim.opt.termguicolors:get() then
      vim.opt.listchars:append({ nbsp = '␣' })
      vim.opt.fillchars:append({ diff = '╱' })
    end
    return true
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
    width = 0.7,
    height = 0.7,
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
        return true
      end,
    })
  end
end

load('plugin/rplugin.vim', 'loaded_remote_plugins', {
  'FileType',
  'BufNew',
  'BufWritePost',
  'BufReadPre',
})
load('provider/python3.vim', 'loaded_python3_provider', {
  'FileType python',
  'BufNew *.py,*.ipynb',
  'BufEnter *.py,*.ipynb',
  'BufWritePost *.py,*.ipynb',
  'BufReadPre *.py,*.ipynb',
})
